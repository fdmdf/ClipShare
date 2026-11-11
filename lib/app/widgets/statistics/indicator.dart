import 'package:clipshare/app/widgets/dot.dart';
import 'package:flutter/cupertino.dart';

class Indicator extends StatelessWidget {
  final String name;
  final Color color;

  const Indicator({super.key, required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Dot(radius: 5, color: color),
        const SizedBox(width: 5),
        Text(name),
      ],
    );
  }
}
