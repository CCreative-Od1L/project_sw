package com.ccreativeod1l.project_sw

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isBiometricAvailable())
                "createKey" -> createKey(result)
                "loadKey" -> loadKey(result)
                "deleteKey" -> deleteKey(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun isBiometricAvailable(): Boolean {
        return BiometricManager.from(this).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG,
        ) == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun createKey(result: MethodChannel.Result) {
        if (!isBiometricAvailable()) {
            result.error(ERROR_UNAVAILABLE, null, null)
            return
        }
        try {
            if (!deleteBiometricMaterialBestEffort()) {
                result.error(ERROR_AUTHENTICATION, null, null)
                return
            }
            val key = generateKeystoreKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val transientKey = ByteArray(TRANSIENT_KEY_LENGTH)
            SecureRandom().nextBytes(transientKey)
            authenticate(
                cipher,
                result,
                onAuthenticationError = { deleteBiometricMaterialBestEffort() },
            ) { authenticatedCipher ->
                try {
                    val ciphertext = authenticatedCipher.doFinal(transientKey)
                    if (!persistEnvelope(authenticatedCipher.iv, ciphertext)) {
                        throw IllegalStateException("Biometric envelope was not persisted")
                    }
                    result.success(transientKey.copyOf())
                } catch (error: Exception) {
                    deleteBiometricMaterialBestEffort()
                    result.error(ERROR_AUTHENTICATION, null, null)
                } finally {
                    transientKey.fill(0)
                }
            }
        } catch (error: KeyPermanentlyInvalidatedException) {
            deleteBiometricMaterialBestEffort()
            result.error(ERROR_INVALIDATED, null, null)
        } catch (error: Exception) {
            deleteBiometricMaterialBestEffort()
            result.error(ERROR_AUTHENTICATION, null, null)
        }
    }

    private fun loadKey(result: MethodChannel.Result) {
        if (!isBiometricAvailable()) {
            result.error(ERROR_UNAVAILABLE, null, null)
            return
        }
        val envelope = readEnvelope()
        if (envelope == null) {
            result.error(ERROR_UNAVAILABLE, null, null)
            return
        }
        var encrypted = envelope.second
        try {
            val key = loadKeystoreKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(GCM_TAG_LENGTH_BITS, envelope.first),
            )
            authenticate(cipher, result) { authenticatedCipher ->
                try {
                    val transientKey = authenticatedCipher.doFinal(encrypted)
                    if (transientKey.size != TRANSIENT_KEY_LENGTH) {
                        transientKey.fill(0)
                        result.error(ERROR_AUTHENTICATION, null, null)
                        return@authenticate
                    }
                    result.success(transientKey.copyOf())
                    transientKey.fill(0)
                } catch (error: Exception) {
                    result.error(ERROR_AUTHENTICATION, null, null)
                } finally {
                    encrypted.fill(0)
                }
            }
        } catch (error: KeyPermanentlyInvalidatedException) {
            encrypted.fill(0)
            result.error(ERROR_INVALIDATED, null, null)
        } catch (error: UserNotAuthenticatedException) {
            encrypted.fill(0)
            result.error(ERROR_AUTHENTICATION, null, null)
        } catch (error: Exception) {
            encrypted.fill(0)
            result.error(ERROR_AUTHENTICATION, null, null)
        }
    }

    private fun deleteKey(result: MethodChannel.Result) {
        try {
            deleteKeystoreKey()
            val preferences = getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val removed = preferences
                .edit()
                .remove(ENVELOPE_KEY)
                .commit()
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply {
                load(null)
            }
            if (removed &&
                !preferences.contains(ENVELOPE_KEY) &&
                !keyStore.containsAlias(KEY_ALIAS)
            ) {
                result.success(null)
            } else {
                result.error(ERROR_AUTHENTICATION, null, null)
            }
        } catch (error: Exception) {
            result.error(ERROR_AUTHENTICATION, null, null)
        }
    }

    private fun authenticate(
        cipher: Cipher,
        result: MethodChannel.Result,
        onAuthenticationError: () -> Unit = {},
        onAuthenticated: (Cipher) -> Unit,
    ) {
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock password vault")
            .setSubtitle("Use biometrics to protect your vault")
            .setNegativeButtonText("Use master password")
            .build()
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    val authenticatedCipher =
                        authenticationResult.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        onAuthenticationError()
                        result.error(ERROR_AUTHENTICATION, null, null)
                    } else {
                        onAuthenticated(authenticatedCipher)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    val normalized = when (errorCode) {
                        BiometricPrompt.ERROR_NO_BIOMETRICS,
                        BiometricPrompt.ERROR_HW_NOT_PRESENT,
                        BiometricPrompt.ERROR_HW_UNAVAILABLE,
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
                        -> ERROR_UNAVAILABLE
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_CANCELED,
                        BiometricPrompt.ERROR_TIMEOUT,
                        -> ERROR_CANCELLED
                        else -> ERROR_AUTHENTICATION
                    }
                    onAuthenticationError()
                    result.error(normalized, null, null)
                }
            },
        )
        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
    }

    private fun generateKeystoreKey(): SecretKey {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }
        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun loadKeystoreKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("Biometric key is missing")
    }

    private fun deleteKeystoreKey() {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }

    private fun deleteBiometricMaterialBestEffort(): Boolean {
        var keyRemoved = false
        var envelopeRemoved = false
        try {
            deleteKeystoreKey()
            keyRemoved = true
        } catch (error: Exception) {
            // The caller still needs a MethodChannel result on cleanup faults.
        }
        try {
            val preferences = getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            envelopeRemoved = preferences
                .edit()
                .remove(ENVELOPE_KEY)
                .commit() && !preferences.contains(ENVELOPE_KEY)
        } catch (error: Exception) {
            // Report failure without letting best-effort cleanup throw.
        }
        return keyRemoved && envelopeRemoved
    }

    private fun persistEnvelope(iv: ByteArray, ciphertext: ByteArray): Boolean {
        val envelope = ByteBuffer.allocate(4 + iv.size + ciphertext.size)
            .putInt(iv.size)
            .put(iv)
            .put(ciphertext)
            .array()
        val encoded = Base64.encodeToString(envelope, Base64.NO_WRAP)
        envelope.fill(0)
        return getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(ENVELOPE_KEY, encoded)
            .commit()
    }

    private fun readEnvelope(): Pair<ByteArray, ByteArray>? {
        val encoded = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(ENVELOPE_KEY, null) ?: return null
        val envelope = try {
            Base64.decode(encoded, Base64.NO_WRAP)
        } catch (error: IllegalArgumentException) {
            return null
        }
        if (envelope.size < 4 + GCM_IV_LENGTH + GCM_TAG_LENGTH_BYTES) {
            envelope.fill(0)
            return null
        }
        val buffer = ByteBuffer.wrap(envelope)
        val ivLength = buffer.int
        if (ivLength != GCM_IV_LENGTH || envelope.size <= 4 + ivLength) {
            envelope.fill(0)
            return null
        }
        val iv = ByteArray(ivLength)
        buffer.get(iv)
        val ciphertext = ByteArray(buffer.remaining())
        buffer.get(ciphertext)
        envelope.fill(0)
        return iv to ciphertext
    }

    companion object {
        private const val CHANNEL_NAME = "project_sw/biometric_key_store"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "project_sw_biometric_k_bio"
        private const val PREFERENCES_NAME = "project_sw_biometric"
        private const val ENVELOPE_KEY = "k_bio_envelope"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TRANSIENT_KEY_LENGTH = 32
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val GCM_TAG_LENGTH_BYTES = GCM_TAG_LENGTH_BITS / 8
        private const val ERROR_UNAVAILABLE = "unavailable"
        private const val ERROR_CANCELLED = "cancelled"
        private const val ERROR_INVALIDATED = "invalidated"
        private const val ERROR_AUTHENTICATION = "authentication_failed"
    }
}
