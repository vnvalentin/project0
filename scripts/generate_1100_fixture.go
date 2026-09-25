package main

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 4 {
		panic("usage: generate_1100_fixture <manifest> <signature> <public-key>")
	}
	manifestPath, signaturePath, publicKeyPath := os.Args[1], os.Args[2], os.Args[3]
	manifest, err := os.ReadFile(manifestPath)
	if err != nil {
		panic(err)
	}
	manifest = bytes.TrimPrefix(manifest, []byte{0xef, 0xbb, 0xbf})
	if !json.Valid(manifest) {
		panic("manifest is not valid JSON")
	}
	if err := os.WriteFile(manifestPath, manifest, 0600); err != nil {
		panic(err)
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}
	digest := sha256.Sum256(manifest)
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		panic(err)
	}
	publicDER, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		panic(err)
	}
	writePEM(publicKeyPath, "PUBLIC KEY", publicDER)
	if err := os.WriteFile(signaturePath, signature, 0600); err != nil {
		panic(err)
	}
	savedSignature, err := os.ReadFile(signaturePath)
	if err != nil {
		panic(err)
	}
	if err := rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, digest[:], savedSignature); err != nil {
		panic(err)
	}
	fmt.Println("Verified test manifest signature; private key was not persisted.")
}

func writePEM(path, kind string, data []byte) {
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: kind, Bytes: data}), 0600); err != nil {
		panic(err)
	}
}
