import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/api/auth.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/stores/user_controller.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/loading_dialog.dart';
import 'package:gh_explorer/utils/toast_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// GitHub 登录页
///
/// 支持两种纯客户端登录方式：
/// 1. Personal Access Token (PAT) 登录：全平台（含 Web）通用，推荐；
/// 2. OAuth Device Flow 登录：移动端与桌面端可用（Web 端受 github.com CORS 限制）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController(
    text: GlobalConstants.oauthClientId,
  );

  bool _obscureToken = true;
  bool _showPatGuide = false;
  bool _showDeviceFlowConfig = false;

  // Device Flow 授权状态
  DeviceCodeResponse? _deviceCode;
  Timer? _pollTimer;
  int _remainingSeconds = 0;
  int _pollIntervalSeconds = 5;
  bool _pollingInFlight = false;

  UserController get _userController => Get.find<UserController>();

  @override
  void dispose() {
    _cancelDeviceFlow();
    _tokenController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }

  /// 取消设备授权轮询定时器并复位在途标记
  void _cancelDeviceFlow() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollingInFlight = false;
  }

  /// 读取系统剪贴板文本并回填至 Token 输入框
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ToastUtils.showToast(context, '剪贴板里没有文本内容');
      return;
    }
    _tokenController.text = text;
    ToastUtils.showToast(context, '已粘贴剪贴板内容');
  }

  /// 唤起外部浏览器打开 GitHub 新建 Token 页面（已预选常用只读与 Star 权限）
  Future<void> _openCreatePatPage() async {
    final uri = Uri.parse(HttpConstants.createPatUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ToastUtils.showToast(context, '无法打开 GitHub 页面，请手动访问');
    }
  }

  /// 表单校验通过后发起 PAT 登录
  Future<void> _submitTokenLogin() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    await _loginWithRawToken(_tokenController.text.trim());
  }

  /// 使用给定令牌请求 `/user` 验证身份、落盘凭证并更新全局用户态
  Future<void> _loginWithRawToken(String rawToken) async {
    LoadingDialog.show(context, message: '正在验证 GitHub 凭证...');
    try {
      final result = await loginWithTokenAPI(rawToken);
      await tokenManager.setToken(result.token, scopes: result.scopes);
      _userController.updateUserInfo(result.user, tokenScopes: result.scopes);
      // 无论成功还是失败，先精确关闭 LoadingDialog 再做 mounted 校验
      LoadingDialog.hide();
      if (!mounted) return;
      ToastUtils.showToast(context, '登录成功，欢迎 ${result.user.displayName}');
      Navigator.pop(context, true);
    } catch (e) {
      LoadingDialog.hide();
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '登录失败，请检查 Token 是否有效'),
      );
    }
  }

  /// 发起 OAuth Device Flow 设备码授权
  Future<void> _startDeviceFlow() async {
    if (kIsWeb) {
      ToastUtils.showToast(context, 'Web 端受限于浏览器跨域策略，请使用 PAT 登录');
      return;
    }
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() => _showDeviceFlowConfig = true);
      ToastUtils.showToast(context, '请先填写 GitHub OAuth App Client ID');
      return;
    }

    LoadingDialog.show(context, message: '正在获取设备授权码...');
    try {
      final res = await requestDeviceCodeAPI(clientId);
      LoadingDialog.hide();
      if (!mounted) return;
      _cancelDeviceFlow();
      setState(() {
        _deviceCode = res;
        _remainingSeconds = res.expiresIn;
        _pollIntervalSeconds = res.interval < 5 ? 5 : res.interval;
      });
      _startPolling(clientId, res.deviceCode);
    } catch (e) {
      LoadingDialog.hide();
      if (!mounted) return;
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '获取授权码失败'),
      );
    }
  }

  /// 启动每秒倒计时并按间隔轮询 GitHub OAuth Token 接口
  void _startPolling(String clientId, String deviceCode) {
    var elapsedSincePoll = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        _cancelDeviceFlow();
        setState(() {
          _deviceCode = null;
          _remainingSeconds = 0;
        });
        ToastUtils.showToast(context, '设备授权码已过期，请重新发起');
        return;
      }
      setState(() {
        _remainingSeconds--;
      });

      elapsedSincePoll++;
      if (elapsedSincePoll < _pollIntervalSeconds || _pollingInFlight) {
        return;
      }
      elapsedSincePoll = 0;
      _pollingInFlight = true;
      try {
        final poll = await pollDeviceAccessTokenAPI(
          clientId: clientId,
          deviceCode: deviceCode,
        );
        if (!mounted) return;
        switch (poll.status) {
          case DeviceTokenStatus.success:
            _cancelDeviceFlow();
            setState(() => _deviceCode = null);
            await _loginWithRawToken(poll.accessToken);
            break;
          case DeviceTokenStatus.slowDown:
            _pollIntervalSeconds += 5;
            break;
          case DeviceTokenStatus.pending:
            break;
          case DeviceTokenStatus.expired:
          case DeviceTokenStatus.denied:
          case DeviceTokenStatus.error:
            _cancelDeviceFlow();
            setState(() => _deviceCode = null);
            ToastUtils.showToast(context, poll.errorMessage);
            break;
        }
      } catch (_) {
        // 轮询期间偶发网络波动忽略，等待下个周期继续轮询
      } finally {
        _pollingInFlight = false;
      }
    });
  }

  /// 复制 8 位授权码并打开 GitHub 设备授权验证页面
  Future<void> _copyCodeAndOpenBrowser(DeviceCodeResponse code) async {
    await Clipboard.setData(ClipboardData(text: code.userCode));
    if (!mounted) return;
    ToastUtils.showToast(context, '已复制授权码 ${code.userCode}，正在前往 GitHub...');
    final uri = Uri.parse(code.verificationUri);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 构造 PAT 输入框样式（含粘贴与明文显隐按钮）
  InputDecoration _tokenInputDecoration() {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: '粘贴 GitHub Token（ghp_... / github_pat_...）',
      hintStyle: AppTextStyles.caption.copyWith(fontSize: 13),
      filled: true,
      fillColor: AppColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.content_paste, size: 18),
            tooltip: '粘贴',
          ),
          IconButton(
            onPressed: () => setState(() => _obscureToken = !_obscureToken),
            icon: Icon(
              _obscureToken
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            tooltip: _obscureToken ? '显示 Token' : '隐藏 Token',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDevice = _deviceCode;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('登录 GitHub'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.brandDark,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.code,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '连接你的 GitHub 账号',
                              style: AppTextStyles.pageTitle,
                            ),
                            SizedBox(height: 4),
                            Text(
                              '登录后解锁点 Star、查看动态、私有仓库及 5000 次/小时 API 配额',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Personal Access Token 登录',
                    style: AppTextStyles.bodyStrong,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submitTokenLogin(),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return '请输入 GitHub Personal Access Token';
                      }
                      if (text.length < 10) {
                        return 'Token 长度过短，请确认完整复制';
                      }
                      return null;
                    },
                    decoration: _tokenInputDecoration(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitTokenLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        '验证并登录',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _openCreatePatPage,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('前往 GitHub 生成 Token'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _showPatGuide = !_showPatGuide),
                        child: Text(_showPatGuide ? '收起指引' : '如何获取？'),
                      ),
                    ],
                  ),
                  if (_showPatGuide) _buildPatGuideCard(),
                  const Divider(height: 32, color: AppColors.divider),
                  _buildDeviceFlowSection(activeDevice),
                  const SizedBox(height: 16),
                  const Text(
                    '说明：令牌仅保存在本机缓存用于直接请求 api.github.com，不会上传至任何第三方服务器。',
                    style: AppTextStyles.captionSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatGuideCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('获取 Classic Token 步骤：', style: AppTextStyles.bodyStrong),
          SizedBox(height: 6),
          Text(
            '1. 点击上方「前往 GitHub 生成 Token」（已自动勾选推荐权限）；\n'
            '2. 建议勾选权限：repo（点 Star 与仓库）、read:user（个人资料）、notifications（通知）；\n'
            '3. 生成后复制以 ghp_ 开头的令牌粘贴到上方输入框即可。',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceFlowSection(DeviceCodeResponse? activeDevice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('OAuth 设备授权登录', style: AppTextStyles.bodyStrong),
            TextButton(
              onPressed: () => setState(
                () => _showDeviceFlowConfig = !_showDeviceFlowConfig,
              ),
              child: Text(
                _showDeviceFlowConfig ? '隐藏 Client ID' : '配置 Client ID',
              ),
            ),
          ],
        ),
        if (kIsWeb)
          const Text(
            'Web 浏览器环境下 GitHub OAuth 端点受跨域限制，请优先使用上方 Token 登录。',
            style: AppTextStyles.caption,
          ),
        if (_showDeviceFlowConfig) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _clientIdController,
            decoration: InputDecoration(
              hintText: '输入你的 GitHub OAuth App Client ID',
              hintStyle: AppTextStyles.caption,
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
        if (activeDevice != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.primary),
            ),
            child: Column(
              children: [
                const Text('请在浏览器中输入以下设备授权码', style: AppTextStyles.bodySmall),
                const SizedBox(height: 8),
                SelectableText(
                  activeDevice.userCode,
                  style: AppTextStyles.pageTitle.copyWith(
                    letterSpacing: 3,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '等待授权确认中（剩余 $_remainingSeconds 秒）',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _copyCodeAndOpenBrowser(activeDevice),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: const Text('复制并前往授权'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () {
                        _cancelDeviceFlow();
                        setState(() => _deviceCode = null);
                      },
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: kIsWeb ? null : _startDeviceFlow,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandDark,
                side: const BorderSide(color: AppColors.divider),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('使用 GitHub 网页设备授权'),
            ),
          ),
        ],
      ],
    );
  }
}
