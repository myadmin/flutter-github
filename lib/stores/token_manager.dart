import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 敏感凭证的读写抽象，便于在单测中注入内存实现。
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 基于 flutter_secure_storage 的凭证存储：
/// Android 使用 Keystore 加密（AES-GCM + RSA-OAEP 包裹），
/// iOS/macOS 使用 Keychain，Web 使用 WebCrypto + localStorage，
/// Windows/Linux 使用系统凭据库。
class SecureSecretStore implements SecretStore {
  const SecureSecretStore({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  /// 安全存储不可用时的内存兜底（如单元测试、缺少系统凭据库的桌面环境），
  /// 保证应用仍可登录，只是重启后需要重新授权。
  static final Map<String, String> _fallback = <String, String>{};
  static bool _pluginUnavailable = false;

  @override
  Future<String?> read(String key) async {
    if (_pluginUnavailable) return _fallback[key];
    try {
      return await storage.read(key: key);
    } on MissingPluginException {
      _pluginUnavailable = true;
      return _fallback[key];
    } catch (error) {
      debugPrint('[SecretStore] 安全存储读取失败，使用内存兜底（$key）：$error');
      return _fallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (_pluginUnavailable) {
      _fallback[key] = value;
      return;
    }
    try {
      await storage.write(key: key, value: value);
    } on MissingPluginException {
      _pluginUnavailable = true;
      _fallback[key] = value;
    } catch (error) {
      debugPrint('[SecretStore] 安全存储写入失败，使用内存兜底（$key）：$error');
      _fallback[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!_pluginUnavailable) {
      try {
        await storage.delete(key: key);
      } on MissingPluginException {
        _pluginUnavailable = true;
      } catch (error) {
        debugPrint('[SecretStore] 安全存储删除失败，清理内存兜底（$key）：$error');
      }
    }
    _fallback.remove(key);
  }
}

/// 本地持久化 GitHub 访问令牌（PAT / OAuth Token）及权限范围。
///
/// 令牌属于敏感凭证，不再以明文写入 SharedPreferences：
/// 统一走 [SecretStore]（默认系统安全存储），并且首次启动时会自动把
/// 历史版本遗留的明文令牌迁移到安全存储后删除明文副本。
class TokenManager {
  TokenManager({SecretStore secretStore = const SecureSecretStore()})
    : _store = secretStore;

  SecretStore _store;

  String _token = '';
  List<String> _scopes = const [];

  @visibleForTesting
  set secretStore(SecretStore value) => _store = value;

  /// 启动时从安全存储读取 token 与 scopes，并迁移历史明文数据
  Future<void> init() async {
    String? storedToken;
    String? storedScopes;
    try {
      storedToken = await _store.read(GlobalConstants.tokenKey);
      storedScopes = await _store.read(GlobalConstants.tokenScopesKey);
    } catch (error) {
      // 安全存储不可用时降级为仅内存保存，避免启动失败
      debugPrint('[TokenManager] 安全存储不可用，令牌仅保存在内存：$error');
    }

    if (storedToken == null || storedToken.isEmpty) {
      final legacy = await _readLegacyPrefs();
      if (legacy.token.isNotEmpty) {
        storedToken = legacy.token;
        storedScopes ??= legacy.scopes;
        await _safeWrite(GlobalConstants.tokenKey, legacy.token);
        if (legacy.scopes.isNotEmpty) {
          await _safeWrite(GlobalConstants.tokenScopesKey, legacy.scopes);
        }
        await _clearLegacyPrefs();
      }
    }

    _token = storedToken ?? '';
    _scopes = _decodeScopes(storedScopes);
  }

  /// 保存 token（可选保存从 `X-OAuth-Scopes` 解析的权限列表）
  Future<void> setToken(String token, {List<String>? scopes}) async {
    _token = token;
    await _safeWrite(GlobalConstants.tokenKey, token);
    if (scopes != null) {
      _scopes = List<String>.unmodifiable(scopes);
      await _safeWrite(GlobalConstants.tokenScopesKey, jsonEncode(_scopes));
    }
  }

  /// 更新已存权限列表
  Future<void> setScopes(List<String> scopes) async {
    _scopes = List<String>.unmodifiable(scopes);
    await _safeWrite(GlobalConstants.tokenScopesKey, jsonEncode(_scopes));
  }

  String getToken() => _token;

  List<String> getScopes() => _scopes;

  /// 是否已登录（本地存在非空 token）
  bool get hasToken => _token.isNotEmpty;

  /// 清除本地 token 与权限信息
  Future<void> removeToken() async {
    _token = '';
    _scopes = const [];
    try {
      await _store.delete(GlobalConstants.tokenKey);
      await _store.delete(GlobalConstants.tokenScopesKey);
    } catch (error) {
      debugPrint('[TokenManager] 清除安全存储失败：$error');
    }
    await _clearLegacyPrefs();
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _store.write(key, value);
    } catch (error) {
      debugPrint('[TokenManager] 写入安全存储失败（$key）：$error');
    }
  }

  List<String> _decodeScopes(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<String>.unmodifiable(decoded.map((e) => e.toString()));
      }
    } on FormatException {
      // 兼容旧格式：逗号分隔
    }
    return List<String>.unmodifiable(
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
  }

  Future<_LegacyToken> _readLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _LegacyToken(
        prefs.getString(GlobalConstants.tokenKey) ?? '',
        (prefs.getStringList(GlobalConstants.tokenScopesKey) ?? const []).join(
          ',',
        ),
      );
    } catch (error) {
      debugPrint('[TokenManager] 读取历史明文令牌失败：$error');
      return const _LegacyToken('', '');
    }
  }

  Future<void> _clearLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(GlobalConstants.tokenKey);
      await prefs.remove(GlobalConstants.tokenScopesKey);
    } catch (error) {
      debugPrint('[TokenManager] 清理历史明文令牌失败：$error');
    }
  }
}

class _LegacyToken {
  const _LegacyToken(this.token, this.scopes);

  final String token;
  final String scopes;
}

final tokenManager = TokenManager();
