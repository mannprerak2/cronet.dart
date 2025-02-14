## 0.0.1+1

* `HttpClientResponse`'s `followRedirects` and `maxRedirects` are now modifiable.
* Fixed: utf8 decoding of newLocation in case of redirects.

## 0.0.1

* HttpClient with QUIC, HTTP2, brotli support.
* HttpClient with a customizable user agent string.
* HttpClient close method (without force close).
* Implemented open, openUrl & other associated methods.
* Response is consumable using 2 styles of APIs. dart:io style and callback based style.
* Different types of Exceptions are implemented.

**Breaking Changes:**

* Custom `SecurityContext` is no longer handled by the client. Users have to handle it in other ways. (To be documented later).
* `userAgent` property is now read-only. Custom userAgent should be passed as a constructor argument.
