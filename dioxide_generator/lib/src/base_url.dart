import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;

const _baseUrlVar = 'baseUrl';

String getBaseUrlVar() => _baseUrlVar;

Parameter buildBaseUrlParameter() => Parameter((p) {
      p
        ..named = true
        ..name = _baseUrlVar
        ..toThis = true;
    });

Field buildBaseUrlFiled() => Field((m) {
      m
        ..name = _baseUrlVar
        ..type = refer('String?')
        ..modifier = FieldModifier.var$;
    });

Iterable<Code> buildBaseUrlDefaultValue(dioxide.RestApi restApi) {
  final baseUrl = restApi.baseUrl;
  if (baseUrl != null && baseUrl.isNotEmpty) {
    return [Code('$_baseUrlVar ??= ${literal(baseUrl)};')];
  } else {
    return [];
  }
}

Map<String, Expression> buildBaseUrlOptions() {
  return {
    _baseUrlVar: refer(_baseUrlVar),
  };
}
