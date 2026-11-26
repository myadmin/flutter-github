import 'package:get/get.dart';
import 'package:gh_explorer/models/user.dart';

/// 全局用户登录态（在 main() 中统一注册一次，跨页面共享）
class UserController extends GetxController {
  /// 当前登录用户信息（未登录时为 [GithubUser.empty]）
  final Rx<GithubUser> user = GithubUser.empty().obs;

  /// 当前令牌拥有的 GitHub OAuth 权限范围列表
  final RxList<String> scopes = <String>[].obs;

  /// 当前是否已登录
  bool get isLoggedIn => user.value.isLoggedIn;

  /// 登录成功或刷新资料后更新全局用户信息与权限范围
  void updateUserInfo(GithubUser newUser, {List<String>? tokenScopes}) {
    user.value = newUser;
    if (tokenScopes != null) {
      scopes.assignAll(tokenScopes);
    }
  }

  /// 退出登录或 401 失效时重置为游客状态
  void clearUserInfo() {
    user.value = GithubUser.empty();
    scopes.clear();
  }
}
