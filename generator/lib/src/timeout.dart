import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

const _sendTimeoutVar = 'sendTimeout';
const _connectTimeoutVar = 'connectTimeout';
const _receiveTimeoutVar = 'receiveTimeout';

Parameter _buildSendTimeoutParameter() => Parameter((p) {
      p
        ..named = true
        ..name = _sendTimeoutVar
        ..toThis = true;
    });

Parameter _buildConnectTimeoutParameter() => Parameter((p) {
      p
        ..named = true
        ..name = _connectTimeoutVar
        ..toThis = true;
    });

Parameter _buildReceiveTimeoutParameter() => Parameter((p) {
      p
        ..named = true
        ..name = _receiveTimeoutVar
        ..toThis = true;
    });

Iterable<Parameter> buildTimeoutParameters() {
  return [
    _buildSendTimeoutParameter(),
    _buildConnectTimeoutParameter(),
    _buildReceiveTimeoutParameter(),
  ];
}

Field _buildSendTimeoutField() => Field((m) {
      m
        ..name = _sendTimeoutVar
        ..type = refer("Duration?")
        ..modifier = FieldModifier.var$;
    });

Field _buildConnectTimeoutField() => Field((m) {
      m
        ..name = _connectTimeoutVar
        ..type = refer("Duration?")
        ..modifier = FieldModifier.var$;
    });

Field _buildReceiveTimeoutField() => Field((m) {
      m
        ..name = _receiveTimeoutVar
        ..type = refer("Duration?")
        ..modifier = FieldModifier.var$;
    });

Iterable<Field> buildTimeoutFields() {
  return [
    _buildSendTimeoutField(),
    _buildConnectTimeoutField(),
    _buildReceiveTimeoutField(),
  ];
}

Iterable<Code> buildTimeoutDefaultValue(Element element) {
  final value = _getTimeoutValue(element);
  return [
    if (value[_sendTimeoutVar] != null) Code('$_sendTimeoutVar ??= const Duration(milliseconds: ${literal(value[_sendTimeoutVar])});'),
    if (value[_connectTimeoutVar] != null) Code('$_connectTimeoutVar ??= const Duration(milliseconds: ${literal(value[_connectTimeoutVar])});'),
    if (value[_receiveTimeoutVar] != null) Code('$_receiveTimeoutVar ??= const Duration(milliseconds: ${literal(value[_receiveTimeoutVar])});'),
  ];
}

Map<String, Expression> buildTimeoutOptions(MethodElement element) {
  final value = _getTimeoutValue(element);
  return {
    _sendTimeoutVar: value[_sendTimeoutVar] != null ? CodeExpression(Code('const Duration(milliseconds: ${literal(value[_sendTimeoutVar])})')) : refer(_sendTimeoutVar),
    _connectTimeoutVar:
        value[_connectTimeoutVar] != null ? CodeExpression(Code('const Duration(milliseconds: ${literal(value[_connectTimeoutVar])})')) : refer(_connectTimeoutVar),
    _receiveTimeoutVar:
        value[_receiveTimeoutVar] != null ? CodeExpression(Code('const Duration(milliseconds: ${literal(value[_receiveTimeoutVar])})')) : refer(_receiveTimeoutVar),
  };
}

Map<String, int?> _getTimeoutValue(Element element) {
  final timeouts = _getTimeoutAnnotation(element);
  final Map<String, int?> expression = {};
  if (timeouts != null) {
    expression[_sendTimeoutVar] = timeouts.peek(_sendTimeoutVar)?.intValue;
    expression[_connectTimeoutVar] = timeouts.peek(_connectTimeoutVar)?.intValue;
    expression[_receiveTimeoutVar] = timeouts.peek(_receiveTimeoutVar)?.intValue;
  }
  return expression;
}

ConstantReader? _getTimeoutAnnotation(Element method) {
  final annotation = typeChecker(dioxide.RequestTimeout).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annotation != null) return ConstantReader(annotation);
  return null;
}
