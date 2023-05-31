import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';
import 'cache.dart';

Map<String, Expression> generateHeaders(MethodElement m) {
  final headers = <String, Expression>{};
  _getHeadersAnnotation(m).forEach((anno) {
    headers.addAll((anno.peek('value')?.mapValue ?? {}).map(
      (k, v) {
        dynamic val;
        if (v == null) {
          val = null;
        } else if (v.type?.isDartCoreBool == true) {
          val = v.toBoolValue();
        } else if (v.type?.isDartCoreString == true) {
          val = v.toStringValue();
        } else if (v.type?.isDartCoreDouble == true) {
          val = v.toDoubleValue();
        } else if (v.type?.isDartCoreInt == true) {
          val = v.toIntValue();
        } else {
          val = v.toStringValue();
        }
        return MapEntry(
          k?.toStringValue() ?? 'null',
          literal(val),
        );
      },
    ));
  });

  final annosInParam = getAnnotations(m, dioxide.Header);
  final headersInParams = annosInParam.map((k, v) {
    final value = v.peek('value')?.stringValue ?? k.displayName;
    return MapEntry(value, refer(k.displayName));
  });
  headers.addAll(headersInParams);

  final cacheMap = generateCache(m);
  headers.addAll(cacheMap);

  return headers;
}

Iterable<ConstantReader> _getHeadersAnnotation(MethodElement method) {
  final annotations = typeChecker(dioxide.Headers).annotationsOf(method, throwOnUnresolved: false);
  return annotations.map((extra) => ConstantReader(extra));
}
