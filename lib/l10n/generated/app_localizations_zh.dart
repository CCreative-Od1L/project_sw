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
  String get generationMode => '模式';

  @override
  String get randomMode => '随机';

  @override
  String get pronounceableMode => '可发音';

  @override
  String generatorLength(int length) {
    return '长度：$length';
  }

  @override
  String get characterSets => '字符集';

  @override
  String get lowercase => '小写字母';

  @override
  String get uppercase => '大写字母';

  @override
  String get digits => '数字';

  @override
  String get symbols => '符号';

  @override
  String get excludeAmbiguous => '排除易混字符';

  @override
  String get pronounceableHint => '可发音模式使用辅音与元音交替组合。';

  @override
  String get generate => '生成';

  @override
  String get copyGeneratedPassword => '复制生成的密码';

  @override
  String get useInEntry => '填入条目';

  @override
  String theoreticalEntropy(String bits) {
    return '理论熵：$bits bit';
  }

  @override
  String get strengthWeak => '弱';

  @override
  String get strengthMedium => '中';

  @override
  String get strengthStrong => '强';

  @override
  String get strengthVeryStrong => '极强';

  @override
  String get generationFailed => '无法生成密码。';

  @override
  String get searchEntries => '搜索条目';

  @override
  String get favoritesOnly => '仅收藏';

  @override
  String get noMatchingEntries => '没有匹配的条目。';

  @override
  String get securitySettingsReadOnly => '安全设置（只读）';

  @override
  String get idleLockPolicy => '空闲锁定';

  @override
  String idleLockPolicyValue(int minutes) {
    return '无操作 $minutes 分钟后锁定。';
  }

  @override
  String get backgroundLockPolicy => '后台锁定';

  @override
  String get backgroundLockPolicyValue => '应用进入后台后立即锁定。';

  @override
  String get clipboardPolicy => '敏感剪贴板';

  @override
  String clipboardPolicyValue(int seconds) {
    return '复制的值将在 $seconds 秒后清除。';
  }

  @override
  String get kdfPolicy => '密码库密钥派生';

  @override
  String get kdfPolicyUnavailable => '解锁密码库后可查看。';

  @override
  String get settingsNoCredentials => '此处不显示凭据或密码库明文。';

  @override
  String get generatorComingSoon => '密码生成器将在下一批功能中加入。';

  @override
  String get settingsComingSoon => '安全设置将在下一批功能中加入。';
}
