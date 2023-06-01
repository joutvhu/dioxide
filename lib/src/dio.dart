import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

/// Extra data that will be passed to dio's request, response, transformer and interceptors.
@immutable
class Extras {
  final Map<String, Object> data;

  const Extras(this.data);
}

@immutable
class Extra {
  final String value;

  const Extra(this.value);
}

@immutable
class CancelRequest {
  const CancelRequest();
}

@immutable
class ReceiveProgress {
  const ReceiveProgress();
}

@immutable
class SendProgress {
  const SendProgress();
}

@immutable
class DioResponseType {
  final ResponseType responseType;

  const DioResponseType(this.responseType);
}

class HttpResponse<T> {
  final T data;
  final Response response;

  HttpResponse(this.data, this.response);
}

@immutable
class DioOptions {
  const DioOptions();
}

@immutable
class RequestTimeout {
  /// Timeout in milliseconds for sending data.
  /// [Dio] will throw the [DioError] with [DioErrorType.sendTimeout] type
  ///  when time out.
  final int? sendTimeout;

  /// Timeout in milliseconds for opening url.
  /// [Dio] will throw the [DioError] with [DioErrorType.connectionTimeout] type
  ///  when time out.
  final int? connectTimeout;

  ///  Timeout in milliseconds for receiving data.
  ///
  ///  Note: [receiveTimeout]  represents a timeout during data transfer! That is to say the
  ///  client has connected to the server, and the server starts to send data to the client.
  ///
  /// [0] meanings no timeout limit.
  final int? receiveTimeout;

  const RequestTimeout({
    this.sendTimeout,
    this.connectTimeout,
    this.receiveTimeout,
  });

  factory RequestTimeout.fromDuration({
    Duration? sendTimeout,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) {
    return RequestTimeout(
      sendTimeout: sendTimeout?.inMicroseconds,
      connectTimeout: connectTimeout?.inMicroseconds,
      receiveTimeout: receiveTimeout?.inMicroseconds,
    );
  }
}

extension FormDataExtension on FormData {
  addList(String key, List<dynamic> values) {
    for (var value in values) {
      if (value == null) continue;
      if (value is MultipartFile) {
        files.add(MapEntry(key, value));
      } else {
        fields.add(MapEntry(key, value.toString()));
      }
    }
  }
}
