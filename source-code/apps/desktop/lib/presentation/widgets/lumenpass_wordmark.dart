import 'package:flutter/material.dart';

const Color lumenPassInk = Color(0xFF191A1B);
const Color lumenPassOrange = Color(0xFFFF5B22);

class LumenPassWordmark extends StatelessWidget {
  const LumenPassWordmark({
    super.key,
    this.fontSize = 18,
    this.lumenColor = lumenPassInk,
    this.passColor = lumenPassOrange,
    this.suffix,
    this.suffixColor,
    this.maxLines = 1,
    this.overflow = TextOverflow.clip,
    this.height = 1,
  });

  final double fontSize;
  final Color lumenColor;
  final Color passColor;
  final String? suffix;
  final Color? suffixColor;
  final int maxLines;
  final TextOverflow overflow;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Lumen', style: TextStyle(color: lumenColor)),
          TextSpan(text: 'Pass', style: TextStyle(color: passColor)),
          if (suffix != null)
            TextSpan(
              text: suffix,
              style: TextStyle(color: suffixColor ?? lumenColor),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        fontFamily: 'Ubuntu Sans',
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: height,
        letterSpacing: 0,
      ),
    );
  }
}
