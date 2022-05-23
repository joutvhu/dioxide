import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

mixin TimeoutGenerator {
  static const _sendTimeout = 'sendTimeout';
  static const _connectTimeout = 'connectTimeout';
  static const _receiveTimeout = 'receiveTimeout';
  static const _sendTimeoutVar = '_sendTimeout';
  static const _connectTimeoutVar = '_connectTimeout';
  static const _receiveTimeoutVar = '_receiveTimeout';

  Field _buildSendTimeoutFiled(int? e) => Field((m) {
        m
          ..name = _sendTimeoutVar
          ..type = refer("int?")
          ..modifier = FieldModifier.var$;
        if (e != null) {
          m.assignment = literal(e).code;
        }
      });

  Field _buildConnectTimeoutFiled(int? e) => Field((m) {
        m
          ..name = _connectTimeoutVar
          ..type = refer("int?")
          ..modifier = FieldModifier.var$;
        if (e != null) {
          m.assignment = literal(e).code;
        }
      });

  Field _buildReceiveTimeoutFiled(int? e) => Field((m) {
        m
          ..name = _receiveTimeoutVar
          ..type = refer("int?")
          ..modifier = FieldModifier.var$;
        if (e != null) {
          m.assignment = literal(e).code;
        }
      });

  List<Field> buildTimeoutFields(Element element) {
    final value = _getTimeoutValue(element);
    return [
      _buildSendTimeoutFiled(value[_sendTimeout]),
      _buildConnectTimeoutFiled(value[_connectTimeout]),
      _buildReceiveTimeoutFiled(value[_receiveTimeout]),
    ];
  }

  Map<String, Expression> buildTimeoutOptions(MethodElement element) {
    final value = _getTimeoutValue(element);
    return {
      _sendTimeout: value[_sendTimeout] != null
          ? literal(value[_sendTimeout])
          : refer(_sendTimeoutVar),
      _connectTimeout: value[_connectTimeout] != null
          ? literal(value[_connectTimeout])
          : refer(_connectTimeoutVar),
      _receiveTimeout: value[_receiveTimeout] != null
          ? literal(value[_receiveTimeout])
          : refer(_receiveTimeoutVar),
    };
  }

  Map<String, int?> _getTimeoutValue(Element element) {
    final timeouts = _getTimeoutAnnotation(element);
    final Map<String, int?> expression = {};
    if (timeouts != null) {
      expression[_sendTimeout] = timeouts.peek(_sendTimeout)?.intValue;
      expression[_connectTimeout] = timeouts.peek(_connectTimeout)?.intValue;
      expression[_receiveTimeout] = timeouts.peek(_receiveTimeout)?.intValue;
    }
    return expression;
  }

  ConstantReader? _getTimeoutAnnotation(Element method) {
    final annotation = _typeChecker(dioxide.RequestTimeout).firstAnnotationOf(method, throwOnUnresolved: false);
    if (annotation != null) return ConstantReader(annotation);
    return null;
  }

  TypeChecker _typeChecker(Type type) => TypeChecker.fromRuntime(type);
}
