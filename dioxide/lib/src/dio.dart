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
