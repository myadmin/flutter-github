import 'package:gh_explorer/models/parsers.dart';

/// GitHub 用户 / 组织信息模型
class GithubUser {
  const GithubUser({
    required this.id,
    required this.login,
    required this.avatarUrl,
    required this.htmlUrl,
    required this.name,
    required this.company,
    required this.blog,
    required this.location,
    required this.email,
    required this.bio,
    required this.type,
    required this.publicRepos,
    required this.publicGists,
    required this.followers,
    required this.following,
    required this.totalPrivateRepos,
    this.createdAt,
  });

  final int id;
  final String login;
  final String avatarUrl;
  final String htmlUrl;
  final String name;
  final String company;
  final String blog;
  final String location;
  final String email;
  final String bio;
  final String type;
  final int publicRepos;
  final int publicGists;
  final int followers;
  final int following;
  final int totalPrivateRepos;

  /// 账号创建时间
  final DateTime? createdAt;

  /// 构造空用户占位对象（未登录游客态使用）
  factory GithubUser.empty() => const GithubUser(
    id: 0,
    login: '',
    avatarUrl: '',
    htmlUrl: '',
    name: '',
    company: '',
    blog: '',
    location: '',
    email: '',
    bio: '',
    type: 'User',
    publicRepos: 0,
    publicGists: 0,
    followers: 0,
    following: 0,
    totalPrivateRepos: 0,
  );

  /// 判断当前是否处于有效登录态
  bool get isLoggedIn => id > 0 && login.isNotEmpty;

  /// 是否为 GitHub 组织账号
  bool get isOrganization => type.toLowerCase() == 'organization';

  /// 优先展示昵称，缺失时回退为 @login
  String get displayName => name.isNotEmpty ? name : login;

  /// 从 GitHub `/user` 或 `/users/{login}` 接口响应构建实例
  factory GithubUser.fromJson(Map<String, dynamic> json) {
    return GithubUser(
      id: asInt(json['id']),
      login: asString(json['login']),
      avatarUrl: asString(json['avatar_url']),
      htmlUrl: asString(json['html_url']),
      name: asString(json['name']),
      company: asString(json['company']),
      blog: asString(json['blog']),
      location: asString(json['location']),
      email: asString(json['email']),
      bio: asString(json['bio']),
      type: asString(json['type'], fallback: 'User'),
      publicRepos: asInt(json['public_repos']),
      publicGists: asInt(json['public_gists']),
      followers: asInt(json['followers']),
      following: asInt(json['following']),
      totalPrivateRepos: asInt(json['total_private_repos']),
      createdAt: asDateTime(json['created_at']),
    );
  }
}
