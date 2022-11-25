/// Define how to parse response json
/// If you want to support more, PR is welcome
enum Parser {
  /// same as [JsonSerializable] but with toMap and fromMap functions.
  MapSerializable,

  /// Each model class must provide 'factory T.fromJson(Map<String, dynamic> json)'
  JsonSerializable,

  /// Each model class must add annotation '@jsonSerializable'
  DartJsonMapper,

  DartSingleMapper,
}

typedef DartSingleSerializer = dynamic Function(String name, dynamic data);

typedef DartSingleDeserializer = dynamic Function(String name, dynamic value);
