class_name Hashing
extends RefCounted
## One way to fingerprint generated art, so every gate compares the same thing.
##
## Golden hashes are taken over an Image's raw RGBA bytes (`Image.get_data()`), never over
## encoded PNG bytes: a PNG carries encoder settings and can differ between platforms for a
## picture that is pixel-identical, which would turn the freshness gate into a flaky one.
##
## `String.sha256_text()` exists; `PackedByteArray` has no such method, so the bytes go
## through a HashingContext here rather than being converted to text at every call site.

static func sha256_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## The fingerprint of what an image LOOKS like, independent of how it is stored.
static func image_digest(img: Image) -> String:
	return sha256_bytes(img.get_data())
