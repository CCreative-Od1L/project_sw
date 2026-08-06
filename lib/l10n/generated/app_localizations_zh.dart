// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Project SW';

  @override
  String get setupTitle => 'Project SW';

  @override
  String get createYourVault => '创建密码库';

  @override
  String get vaultDescription => '加密密码库将创建在此设备上。';

  @override
  String get masterPassword => '主密码';

  @override
  String get optimizingSecurityParameters => '正在优化安全参数…';

  @override
  String optimizingSecurityParametersProgress(int completed, int total) {
    return '正在优化安全参数… $completed/$total';
  }

  @override
  String get createVault => '创建密码库';

  @override
  String get vaultCreated => '密码库已创建';

  @override
  String get securityParametersOptimized => '已针对本设备优化安全参数：';

  @override
  String argon2idParameters(int memoryMiB, int iterations, int parallelism) {
    return 'Argon2id：m=$memoryMiB MiB，t=$iterations，p=$parallelism';
  }

  @override
  String get continueToUnlock => '继续解锁';

  @override
  String get vaultCreationFailed => '无法完成密码库创建。';

  @override
  String get unlockVault => '解锁密码库';

  @override
  String get unlockYourVault => '解锁你的密码库';

  @override
  String get incorrectMasterPassword => '主密码不正确。';

  @override
  String get vaultUnlockFailed => '无法完成密码库解锁。';

  @override
  String get unlock => '解锁';

  @override
  String get vault => '密码库';

  @override
  String get generator => '密码生成器';

  @override
  String get settings => '设置';

  @override
  String get vaultUnlocked => '密码库已解锁';

  @override
  String get noEntries => '还没有添加条目。';

  @override
  String get addEntry => '添加条目';

  @override
  String get name => '名称';

  @override
  String get url => '网址';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get notes => '备注';

  @override
  String get favorite => '收藏';

  @override
  String get saveEntry => '保存条目';

  @override
  String get lockVault => '锁定密码库';

  @override
  String get entryDetail => '条目详情';

  @override
  String get delete => '删除';

  @override
  String get close => '关闭';

  @override
  String get save => '保存';

  @override
  String get entrySaveFailed => '无法保存条目。';

  @override
  String get copySensitiveValue => '复制敏感值';

  @override
  String get copyPassword => '复制密码';

  @override
  String get copySecretField => '复制秘密字段';

  @override
  String sensitiveCopiedClearsIn(int seconds) {
    return '敏感值已复制，将在 $seconds 秒后清除';
  }

  @override
  String get clipboardCleared => '剪贴板已清除';

  @override
  String get clipboardChangedNewerKept => '剪贴板内容已变化，保留新内容';

  @override
  String get generatorComingSoon => '密码生成器将在下一批功能中加入。';

  @override
  String get settingsComingSoon => '安全设置将在下一批功能中加入。';
}
