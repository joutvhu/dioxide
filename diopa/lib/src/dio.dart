import 'package:meta/meta.dart';
import 'package:dio/dio.dart';

@immutable
class Extras {
  final Map<String, Object> data;

  const Extras(this.data);
}

@immutable
class Extra {
  final String name;
  final Object value;

  const Extra(this.name, this.value);
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
