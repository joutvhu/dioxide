# Dioxide

Dioxide is a type conversion [dio](https://github.com/flutterchina/dio/) client generator.

## Using

### Add dependencies

```yaml
dependencies:
  dioxide: ^0.1.1

dev_dependencies:
  build_runner: ^2.2.0
  dioxide_generator: ^0.1.1+3
```

### Define and Generate your API

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:dio/dio.dart';
import 'package:dioxide/dioxide.dart';

part 'example.g.dart';

@RestApi(baseUrl: "http://localhost:8080/api/Task")
abstract class RestClient {
  factory RestClient(Dio dio, {String baseUrl}) = _RestClient;

  @GetRequest()
  Future<List<Task>> getTasks();
}

@JsonSerializable()
class Task {
  String? id;
  String? name;
  String? avatar;
  String? createdAt;

  Task({this.id, this.name, this.avatar, this.createdAt});

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

  Map<String, dynamic> toJson() => _$TaskToJson(this);
}
```

then run the generator

```shell
# dart
pub run build_runner build

# flutter
flutter pub run build_runner build
```

## More

### Type Conversion

> Before you use the type conversion, please make sure that a ` factory Task.fromJson(Map<String, dynamic> json)` must be provided for each model class. `json_serializable` is the recommanded to be used as the serialization tool.

```dart
@GetRequest("/tasks") Future<List<Task>> getTasks();

@JsonSerializable()
class Task {
  String name;
  Task({this.name});
  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}
```

### HTTP Methods

The HTTP methods in the below sample are supported.

```dart
@GetRequest("/tasks/{id}")
Future<Task> getTask(@Path("id") String id);

@GetRequest('/demo')
Future<String> queries(@Queries() Map<String, dynamic> queries);

@GetRequest("/search")
Future<String> namedExample(
    @Query("name") String name,
    @Query("tag") String tag,
);

@PatchRequest("/tasks/{id}")
Future<Task> updateTaskPart(@Path() String id, @Body() Map<String, dynamic> map);

@PutRequest("/tasks/{id}")
Future<Task> updateTask(@Path() String id, @Body() Task task);

@DeleteRequest("/tasks/{id}")
Future<void> deleteTask(@Path() String id);

@PostRequest("/tasks")
Future<Task> createTask(@Body() Task task);

@PostRequest("/post")
Future<void> createNewTaskFromFile(@Part() File file);

@PostRequest("/post")
@FormUrlEncoded()
Future<String> postUrlEncodedFormData(@Field() String hello);
```

### Get original HTTP response

```dart
@GetRequest("/tasks/{id}")
Future<HttpResponse<Task>> getTask(@Path("id") String id);

@GetRequest("/tasks")
Future<HttpResponse<List<Task>>> getTasks();
```

### Get dio Response

```dart
@GetRequest("/file/{fileId}")
@DioResponseType(ResponseType.stream)
Future<Response<ResponseBody>> getTask(@Path("fileId") String id);
```

### HTTP Header

* Add a HTTP header from the parameter of the method

  ```dart
  @GetRequest("/tasks")
  Future<Task> getTasks(@Header("Content-Type") String contentType );
  ```

* Add static HTTP headers

  ```dart
  @GetRequest("/tasks")
  @Headers(<String, dynamic>{
  	"Content-Type" : "application/json",
  	"Custom-Header" : "Your header"
  })
  Future<Task> getTasks();
  ```

### Multiple endpoints support

If you want to use multiple endpoints to your `RestClient`, you should pass your base url when you initiate `RestClient`. Any value defined in `RestApi` will be ignored.

```dart
@RestApi(baseUrl: "this url will be ignored if baseUrl is passed")
abstract class RestClient {
  factory RestClient(Dio dio, {String baseUrl}) = _RestClient;
}

final client = RestClient(dio, baseUrl: "your base url");
```

If you want to use the base url from `dio.option.baseUrl`, which has lowest priority, please don't pass any parameter to `RestApi` annotation and `RestClient`'s structure method. 

### Set request timeout

```dart
@RestApi(baseUrl: 'http://localhost:8080/api/Report')
@RequestTimeout(connectTimeout: 5000, sendTimeout: 5000, receiveTimeout: 5000)
abstract class ReportClient {
  @GetRequest("/generate")
  @RequestTimeout(sendTimeout: 15000, receiveTimeout: 30000)
  @DioResponseType(ResponseType.stream)
  Future<Response<ResponseBody>> getTask(@Queries() Map<String, dynamic> queries);
}
```
