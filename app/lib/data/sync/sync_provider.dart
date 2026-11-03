import 'dart:async';

/// 远端文档。
class RemoteDocument {
  /// 文件内容（UTF-8 文本）。
  final String content;

  /// 远端最后修改时间（拿不到则为 null）。
  final DateTime? modifiedAt;

  /// 版本标记（WebDAV 的 ETag / 百度网盘的 md5），用于快速判断是否需要传输。
  final String? versionTag;

  const RemoteDocument({required this.content, this.modifiedAt, this.versionTag});
}

/// 同步传输层抽象。
///
/// 只做「读一个文档 / 写一个文档 / 测连通性」三件事，
/// 所有同步语义（合并、冲突处理）都在 [SyncEngine] 里，与具体网盘无关。
/// 这样新增一种网盘只需要实现这个接口，不需要碰同步逻辑。
abstract class SyncProvider {
  /// 展示名，用于日志与界面。
  String get displayName;

  /// 测试连通性与凭据是否有效。失败时抛 [SyncException]。
  Future<void> testConnection();

  /// 读取远端文档；不存在时返回 null。
  Future<RemoteDocument?> download();

  /// 写入远端文档（覆盖），必要时自动创建目录。
  Future<void> upload(String content);

  /// 释放底层连接。
  void dispose() {}
}
