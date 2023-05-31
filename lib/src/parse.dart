/// Define how to parse response json
/// If you want to support more, PR is welcome
enum Parser {
  /// same as [JsonSerializable] but with toMap and fromMap functions.
  // ignore: constant_identifier_names
  MapSerializable,

  /// Each model class must provide 'factory T.fromJson(Map<String, dynamic> json)'
  // ignore: constant_identifier_names
  JsonSerializable,

  /// Each model class must add annotation '@jsonSerializable'
  // ignore: constant_identifier_names
  DartJsonMapper,

  // ignore: constant_identifier_names
  DartSingleMapper,
}

typedef DartSingleSerializer = dynamic Function(String name, dynamic data);

typedef DartSingleDeserializer = dynamic Function(String name, dynamic value);
