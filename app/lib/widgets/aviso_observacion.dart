import 'package:flutter/material.dart';

/// La observación que dejó el transportista al entregar.
class AvisoObservacion extends StatelessWidget {
  const AvisoObservacion({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDCB8F)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_note, size: 20, color: Color(0xFF8A4F00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Observación: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: texto),
                ],
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF5C3A00)),
            ),
          ),
        ],
      ),
    );
  }
}
