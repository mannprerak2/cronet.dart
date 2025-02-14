// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'globals.dart';
import 'http_callback_handler.dart';
import 'http_client_response.dart';
import 'third_party/cronet/generated_bindings.dart';

/// HTTP request for a client connection.
///
/// It handles all of the Http Requests made by [HttpClient].
/// Provides two ways to get data from the request.
/// [registerCallbacks] or a [HttpClientResponse] which is a
/// [Stream<List<int>>]. Either of them can be used at a time.
///
/// Example Usage:
/// ```dart
/// final client = HttpClient();
/// client.getUrl(Uri.parse('https://example.com/'))
///   .then((HttpClientRequest request) {
///   return request.close();
/// }).then((HttpClientResponse response) {
///   // Here you got the raw data.
///   // Use it as you like.
/// });
/// ```
abstract class HttpClientRequest implements io.IOSink {
  /// Returns [Future] of [HttpClientResponse] which can be listened for server
  /// response.
  ///
  /// Throws [UrlRequestError] if request can't be initiated.
  @override
  Future<HttpClientResponse> close();

  /// This is same as [close]. A [HttpClientResponse] future that will complete
  /// once the request is successfully made.
  ///
  /// If any problems occurs before the response is available, this future will
  /// completes with an [UrlRequestError].
  @override
  Future<HttpClientResponse> get done;

  /// Follow the redirects.
  bool get followRedirects;
  set followRedirects(bool follow);

  /// Maximum numbers of redirects to follow.
  /// Have no effect if [followRedirects] is set to false.
  int get maxRedirects;
  set maxRedirects(int redirects);

  /// The uri of the request.
  Uri get uri;
}

/// Implementation of [HttpClientRequest].
class HttpClientRequestImpl implements HttpClientRequest {
  final Uri _uri;
  final String _method;
  final Pointer<Cronet_Engine> _cronetEngine;
  final CallbackHandler _callbackHandler;
  final Pointer<Cronet_UrlRequest> _request;

  /// Holds the function to clean up after the request is done (if nessesary).
  ///
  /// Implemented by: http_client.dart.
  final void Function(HttpClientRequest) _clientCleanup;

  @override
  Encoding encoding;

  /// Initiates a [HttpClientRequestImpl]. It is meant to be used by a
  /// [HttpClient].
  HttpClientRequestImpl(
      this._uri, this._method, this._cronetEngine, this._clientCleanup,
      {this.encoding = utf8})
      : _callbackHandler =
            CallbackHandler(wrapper.SampleExecutorCreate(), ReceivePort()),
        _request = cronet.Cronet_UrlRequest_Create() {
    // Register the native port to C side.
    wrapper.RegisterCallbackHandler(
        _callbackHandler.receivePort.sendPort.nativePort, _request.cast());
  }

  // Starts the request.
  void _startRequest() {
    final requestParams = cronet.Cronet_UrlRequestParams_Create();
    if (requestParams == nullptr) throw Error();
    // TODO: ISSUE https://github.com/dart-lang/ffigen/issues/22
    cronet.Cronet_UrlRequestParams_http_method_set(
        requestParams, _method.toNativeUtf8().cast<Int8>());
    wrapper.InitSampleExecutor(_callbackHandler.executor);
    final cronetCallbacks = cronet.Cronet_UrlRequestCallback_CreateWith(
      wrapper.addresses.OnRedirectReceived.cast(),
      wrapper.addresses.OnResponseStarted.cast(),
      wrapper.addresses.OnReadCompleted.cast(),
      wrapper.addresses.OnSucceeded.cast(),
      wrapper.addresses.OnFailed.cast(),
      wrapper.addresses.OnCanceled.cast(),
    );
    final res = cronet.Cronet_UrlRequest_InitWithParams(
        _request,
        _cronetEngine,
        _uri.toString().toNativeUtf8().cast<Int8>(),
        requestParams,
        cronetCallbacks,
        wrapper.SampleExecutor_Cronet_ExecutorPtr_get(_callbackHandler.executor)
            .cast());

    if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
      throw UrlRequestError(res);
    }

    final res2 = cronet.Cronet_UrlRequest_Start(_request);
    if (res2 != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
      throw UrlRequestError(res2);
    }
    _callbackHandler.listen(_request, () => _clientCleanup(this));
  }

  /// Returns [Future] of [HttpClientResponse] which can be listened for server
  /// response.
  ///
  /// Throws [UrlRequestError] if request can't be initiated.
  @override
  Future<HttpClientResponse> close() {
    return Future(() {
      _startRequest();
      return HttpClientResponseImpl(_callbackHandler.stream);
    });
  }

  /// This is same as [close]. A [HttpClientResponse] future that will complete
  /// once the request is successfully made.
  ///
  /// If any problems occurs before the response is available, this future will
  /// completes with an [UrlRequestError].
  @override
  Future<HttpClientResponse> get done => close();

  /// Follow the redirects.
  @override
  bool get followRedirects => _callbackHandler.followRedirects;
  @override
  set followRedirects(bool follow) {
    _callbackHandler.followRedirects = follow;
  }

  /// Maximum numbers of redirects to follow.
  /// Have no effect if [followRedirects] is set to false.
  @override
  int get maxRedirects => _callbackHandler.maxRedirects;
  @override
  set maxRedirects(int redirects) {
    _callbackHandler.maxRedirects = redirects;
  }

  /// The uri of the request.
  @override
  Uri get uri => _uri;

  @override
  void add(List<int> data) {
    // TODO: implement add
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // TODO: implement addError
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    // TODO: implement addStream
    throw UnimplementedError();
  }

  @override
  Future flush() {
    // TODO: implement flush
    throw UnimplementedError();
  }

  @override
  void write(Object? object) {
    final string = '$object';
    if (string.isEmpty) return;
    add(encoding.encode(string));
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    final iterator = objects.iterator;
    if (!iterator.moveNext()) return;
    if (separator.isEmpty) {
      do {
        write(iterator.current);
      } while (iterator.moveNext());
    } else {
      write(iterator.current);
      while (iterator.moveNext()) {
        write(separator);
        write(iterator.current);
      }
    }
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }
}
