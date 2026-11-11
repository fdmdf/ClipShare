import 'package:clipshare/app/widgets/statistics/indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:graphic/graphic.dart';

class Indicators extends StatelessWidget {
  final List<String> names;
  final String title;
  final AlignmentGeometry? titleAlign;

  const Indicators({
    super.key,
    required this.names,
    required this.title,
    this.titleAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: Align(
              alignment: titleAlign ?? Alignment.center,
              child: Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              names.length,
              (index) {
                return Container(
                  margin: names.length != 1 && names.length - 1 != index
                      ? const EdgeInsets.only(right: 10)
                      : null,
                  child: Indicator(
                    name: names[index],
                    color: Defaults.colors10[index % Defaults.colors10.length],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
