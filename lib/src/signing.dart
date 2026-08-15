import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bundle.dart';

/// Whether this build can produce ed25519 signatures.
///
/// Kept as a constant rather than assumed, because the packaging CLI promises
/// to say "signing unavailable in this build" rather than silently emit an
/// unsigned bundle when someone passed `--key`.
const bool kSigningAvailable = true;

/// The signature algorithm name written into `signature.json`.
const String kSignatureAlgorithm = 'ed25519';

/// A signing key that could not be read.
final class SigningKeyError implements Exception {
  /// Creates a key error.
  const SigningKeyError(this.message);

  /// What was wrong with it.
  final String message;

  @override
  String toString() => message;
}

/// Reads an ed25519 seed out of [bytes].
///
/// Accepts, in order: 32 raw bytes, 64 raw bytes (seed followed by public key),
/// 64 hex characters, or base64 decoding to 32 or 64 bytes. Whitespace is
/// ignored so a key file can end with a newline.
Uint8List parseEd25519Seed(List<int> bytes) {
  if (bytes.length == 32) {
    return Uint8List.fromList(bytes);
  }
  if (bytes.length == 64 && !_looksTextual(bytes)) {
    return Uint8List.fromList(bytes.sublist(0, 32));
  }
  final String text;
  try {
    text = utf8.decode(bytes).replaceAll(RegExp(r'\s'), '');
  } on FormatException {
    throw const SigningKeyError(
      'key file is neither 32 raw bytes nor text this tool can decode',
    );
  }
  if (text.isEmpty) {
    throw const SigningKeyError('key file is empty');
  }
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) {
    return Uint8List.fromList(<int>[
      for (var i = 0; i < 64; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ]);
  }
  final Uint8List decoded;
  try {
    decoded = base64.decode(base64.normalize(text));
  } on FormatException {
    throw const SigningKeyError(
      'key must be 32 raw bytes, 64 hex characters, or base64',
    );
  }
  if (decoded.length == 32) {
    return decoded;
  }
  if (decoded.length == 64) {
    return Uint8List.fromList(decoded.sublist(0, 32));
  }
  throw SigningKeyError(
    'key decodes to ${decoded.length} bytes; an ed25519 seed is 32',
  );
}

/// The bytes an ed25519 signature is taken over for [digestHex].
///
/// The signature is detached and covers the digest recorded in
/// `integrity.json`, as its lowercase hex ASCII. Signing the text rather than
/// the raw hash keeps `signature.json` self-describing: what was signed is
/// literally the string in the `digest` field.
Uint8List signedPayload(String digestHex) =>
    Uint8List.fromList(ascii.encode(digestHex));

/// A short, stable identifier for a public key.
String keyIdFor(List<int> publicKey) => sha256Hex(publicKey).substring(0, 8);

/// Signs [digestHex] with the ed25519 key [seed] and returns `signature.json`.
Future<Map<String, Object?>> signBundleDigest({
  required String digestHex,
  required Uint8List seed,
}) async {
  final Ed25519 algorithm = Ed25519();
  final KeyPair keyPair = await algorithm.newKeyPairFromSeed(seed);
  final SimplePublicKey publicKey =
      await keyPair.extractPublicKey() as SimplePublicKey;
  final Signature signature = await algorithm.sign(
    signedPayload(digestHex),
    keyPair: keyPair,
  );
  return <String, Object?>{
    'signed': true,
    'algorithm': kSignatureAlgorithm,
    'publicKey': base64.encode(publicKey.bytes),
    'signature': base64.encode(signature.bytes),
    'keyId': keyIdFor(publicKey.bytes),
    'digest': digestHex,
  };
}

/// Verifies an ed25519 [signature] over [digestHex] under [publicKey].
Future<bool> verifyBundleSignature({
  required String digestHex,
  required List<int> publicKey,
  required List<int> signature,
}) async {
  if (publicKey.length != 32 || signature.length != 64) {
    return false;
  }
  final Ed25519 algorithm = Ed25519();
  return algorithm.verify(
    signedPayload(digestHex),
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}

/// Derives the public key for the seed [seed], for `--key` round-trips.
Future<Uint8List> publicKeyForSeed(Uint8List seed) async {
  final KeyPair keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final SimplePublicKey publicKey =
      await keyPair.extractPublicKey() as SimplePublicKey;
  return Uint8List.fromList(publicKey.bytes);
}

bool _looksTextual(List<int> bytes) =>
    bytes.every((int b) => b == 0x0a || b == 0x0d || (b >= 0x20 && b < 0x7f));
