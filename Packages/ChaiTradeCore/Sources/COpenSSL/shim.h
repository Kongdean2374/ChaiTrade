#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/rand.h>
#include <openssl/kdf.h>
static inline int chai_gcm(int encrypt, const unsigned char *key, const unsigned char *nonce, const unsigned char *input, int length, unsigned char *output, unsigned char *tag) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return 0;
    int out = 0, final = 0, ok = 1;
    ok &= EVP_CipherInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL, encrypt);
    ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
    ok &= EVP_CipherInit_ex(ctx, NULL, NULL, key, nonce, encrypt);
    ok &= EVP_CipherUpdate(ctx, output, &out, input, length);
    if (!encrypt) ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, tag);
    ok &= EVP_CipherFinal_ex(ctx, output+out, &final);
    if (encrypt) ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}
