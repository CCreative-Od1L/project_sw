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
  String get useBiometric => '使用生物识别解锁';

  @override
  String get biometricCancelled => '已取消生物识别解锁。';

  @override
  String get biometricInvalidated => '生物识别设置已变化。请使用主密码解锁后重新设置。';

  @override
  String get biometricUnavailable => '当前无法使用生物识别，请使用主密码。';

  @override
  String get biometricUnlockFailed => '无法完成生物识别解锁。';

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
  String get sensitiveCopied => '密码已复制到剪贴板';

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
  String get securitySettingsReadOnly => '安全设置';

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
    return '应用将尝试在 $seconds 秒后清除复制的值；不保证 Android 各厂商及第三方输入法的剪贴板能够被正常清除。';
  }

  @override
  String get kdfPolicy => '密码库密钥派生';

  @override
  String get kdfPolicyUnavailable => '解锁密码库后可查看。';

  @override
  String get settingsNoCredentials => '此处不显示凭据或密码库明文。';

  @override
  String get masterPasswordSettings => '主密码';

  @override
  String get masterPasswordChangeDescription => '修改时会生成新的盐并重新包裹密码库密钥，不会重新加密条目。';

  @override
  String get changeMasterPassword => '修改主密码';

  @override
  String get changeMasterPasswordTitle => '修改主密码';

  @override
  String get masterPasswordChangeWarning =>
      '此安全敏感操作会验证当前主密码。请妥善保管新主密码；没有有效的生物恢复路径时无法找回。';

  @override
  String get currentMasterPassword => '当前主密码';

  @override
  String get newMasterPassword => '新主密码';

  @override
  String get confirmNewMasterPassword => '确认新主密码';

  @override
  String get changePassword => '修改密码';

  @override
  String get masterPasswordChanged => '主密码已修改';

  @override
  String get currentMasterPasswordInvalid => '当前主密码不正确。';

  @override
  String get newMasterPasswordRequired => '请输入新主密码。';

  @override
  String get newMasterPasswordsDoNotMatch => '两次输入的新主密码不一致。';

  @override
  String get masterPasswordChangeFailed => '无法修改主密码。';

  @override
  String get recoverWithBiometrics => '使用生物识别恢复';

  @override
  String get recoverMasterPasswordTitle => '恢复主密码';

  @override
  String get masterPasswordRecoveryWarning =>
      '任何通过此次生物识别验证的人都可以通过设置新主密码接管密码库。请仅在可信设备上继续。';

  @override
  String get recoverPassword => '恢复密码';

  @override
  String get masterPasswordRecovered => '主密码已恢复';

  @override
  String get syncRecoveryBackup => '请在冷备设备上同步更新新的主密码。';

  @override
  String masterPasswordStrengthLabel(String strength) {
    return '密码强度：$strength';
  }

  @override
  String get newMasterPasswordTooWeak => '请选择强度更高的主密码。';

  @override
  String get masterPasswordRecoveryUnavailable => '密码恢复目前不可用。';

  @override
  String get masterPasswordRecoveryCancelled => '已取消生物识别确认。';

  @override
  String get masterPasswordRecoveryBiometricUnavailable => '生物识别确认不可用，密码库未被修改。';

  @override
  String get masterPasswordRecoveryFailed => '无法恢复主密码。';

  @override
  String get biometricSettings => '生物识别解锁';

  @override
  String get biometricSecurityBoundary =>
      '生物识别只会释放受设备保护的密码库密钥。应用不会保存主密码，主密码始终可作为退路。';

  @override
  String get biometricEnabled => '此设备已启用生物识别解锁。';

  @override
  String get biometricNotEnabled => '尚未启用生物识别解锁。';

  @override
  String get enableBiometric => '启用生物识别解锁';

  @override
  String get disableBiometric => '停用生物识别解锁';

  @override
  String get resetBiometric => '重新设置生物识别解锁';

  @override
  String get confirmEnableBiometric => '要在此设备上启用生物识别解锁吗？你仍然可以使用主密码。';

  @override
  String get confirmDisableBiometric => '要停用生物识别解锁吗？主密码仍然可用。';

  @override
  String get biometricSetupFailed => '无法修改生物识别设置。';

  @override
  String get biometricSettingsInvalidated => '生物识别设置已变化。请使用主密码解锁后再重新设置。';

  @override
  String get stepUpTitle => '需要主密码验证';

  @override
  String get stepUpDescription => '此安全敏感操作需要主密码验证；仅使用生物识别解锁不足以执行此操作。';

  @override
  String get confirmMasterPassword => '验证主密码';

  @override
  String get stepUpInvalidPassword => '主密码不正确，会话状态未改变。';

  @override
  String get stepUpFailed => '无法完成主密码验证。';

  @override
  String get stepUpUnavailable => '密码库已不再处于解锁状态，请重新解锁后继续。';

  @override
  String get generatorComingSoon => '密码生成器将在下一批功能中加入。';

  @override
  String get settingsComingSoon => '安全设置将在下一批功能中加入。';
}
