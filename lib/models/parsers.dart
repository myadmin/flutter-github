/// 模型反序列化的公共安全取值工具（复用 hm_shop 约定）
///
/// 统一做「任意 JSON 值 -> 目标类型」的显式安全转换，
/// 配合 `strict-casts` 与 `avoid_dynamic_calls` 杜绝运行时类型错误。
library;

/// 转成字符串；null 与空串统一返回 [fallback]。
String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

/// 转成整数；非法值与 null 返回 [fallback]。
int asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
}

/// 转成布尔值；兼容 `true` / `"true"` / `1` / `"1"`，其余返回 [fallback]。
bool asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

/// 解析 ISO-8601 时间字符串；空或非法值返回 null。
DateTime? asDateTime(dynamic value) {
  if (value is DateTime) return value;
  final text = asString(value).trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

/// 把 json 里的数组安全转成模型列表；null 与非数组统一返回空列表。
List<T> asList<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 把 json 里的数组安全转成字符串列表；null 与非数组返回空列表。
List<String> asStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .where((item) => item != null)
      .map((item) => item.toString())
      .toList();
}

/// 把接口返回值收窄成对象；结构不符时抛 [FormatException]。
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('期望接口返回对象，实际为 ${value.runtimeType}');
}

/// 把接口返回的数组收窄成模型列表；结构不符时抛 [FormatException]。
List<T> asModelList<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) {
    throw FormatException('期望接口返回数组，实际为 ${value.runtimeType}');
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => fromJson(item.cast<String, dynamic>()))
      .toList();
}

/// 把可选嵌套对象安全转成 Map；null 与非对象返回空 Map。
Map<String, dynamic> asMapOrEmpty(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

/// 把可选嵌套对象安全转成 Map；null 与非对象返回 null。
Map<String, dynamic>? asMapOrNull(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}
