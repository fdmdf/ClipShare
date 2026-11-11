import 'package:flutter/material.dart';

class HoverClickWrapper extends StatefulWidget {
  final Color defaultColor;
  final Color hoverColor;
  final Color clickColor;
  final Widget child;
  final bool disabled;

  const HoverClickWrapper({
    super.key,
    required this.child,
    this.disabled = false,
    this.defaultColor = Colors.transparent,
    this.hoverColor = Colors.transparent,
    this.clickColor = Colors.transparent,
  });

  @override
  State<StatefulWidget> createState() => _HoverClickWrapperState();
}

class _HoverClickWrapperState extends State<HoverClickWrapper> {
  bool _isHovered = false;
  bool _isClicked = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isClicked = true),
        onTapUp: (_) => setState(() => _isClicked = false),
        onTapCancel: () => setState(() => _isClicked = false),
        child: Container(
          decoration: BoxDecoration(
            color: widget.disabled
                ? null
                : _isClicked
                    ? widget.clickColor
                    : _isHovered
                        ? widget.hoverColor
                        : widget.defaultColor,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
