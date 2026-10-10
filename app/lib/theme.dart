import 'package:flutter/material.dart';

/// Colores del diseño "petróleo y menta" elegido para IPESA. Un solo lugar
/// para que todas las pantallas usen exactamente los mismos tonos.
abstract final class Ipesa {
  static const petroleo = Color(0xFF0F4C5C);
  static const turquesa = Color(0xFF1B7F79);
  static const menta = Color(0xFFE2F1EE);
  static const mentaBorde = Color(0xFFB7D3CE);
  static const fondo = Color(0xFFF6F8F7);
  static const superficie = Colors.white;
  static const texto = Color(0xFF14232A);
  static const textoSuave = Color(0xFF56666B);
  static const etiqueta = Color(0xFF34454B);
  static const borde = Color(0xFFD5DEDC);
  static const segmento = Color(0xFFE6ECEA);
  static const suaveSobrePetroleo = Color(0xFFBFD9D5);

  static const mapaFondo = Color(0xFFE7ECE9);

  static const fuenteTitulos = 'Manrope';
  static const fuenteTexto = 'SourceSans3';

  static const radio = 20.0;
  static const radioCampo = 14.0;

  static const sombraSuave = [
    BoxShadow(color: Color(0x0F14232A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static TextStyle titulo(double size, {Color color = petroleo}) => TextStyle(
    fontFamily: fuenteTitulos,
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: color,
  );
}

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: Ipesa.petroleo,
        brightness: Brightness.light,
      ).copyWith(
        primary: Ipesa.petroleo,
        onPrimary: Colors.white,
        secondary: Ipesa.turquesa,
        onSecondary: Colors.white,
        secondaryContainer: Ipesa.menta,
        onSecondaryContainer: Ipesa.petroleo,
        surface: Ipesa.fondo,
        onSurface: Ipesa.texto,
        onSurfaceVariant: Ipesa.textoSuave,
        outline: Ipesa.borde,
        outlineVariant: Ipesa.borde,
      );

  final radioCampo = BorderRadius.circular(Ipesa.radioCampo);
  const titulos = TextStyle(fontFamily: Ipesa.fuenteTitulos);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: Ipesa.fuenteTexto,
    scaffoldBackgroundColor: Ipesa.fondo,
    visualDensity: VisualDensity.standard,

    appBarTheme: AppBarTheme(
      backgroundColor: Ipesa.fondo,
      foregroundColor: Ipesa.petroleo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Ipesa.titulo(20),
    ),

    textTheme: TextTheme(
      headlineMedium: titulos.copyWith(
        fontWeight: FontWeight.w800,
        color: Ipesa.petroleo,
      ),
      headlineSmall: titulos.copyWith(
        fontWeight: FontWeight.w800,
        color: Ipesa.petroleo,
      ),
      titleLarge: titulos.copyWith(
        fontWeight: FontWeight.w800,
        color: Ipesa.petroleo,
      ),
      titleMedium: titulos.copyWith(fontWeight: FontWeight.w700),
      labelLarge: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Ipesa.etiqueta,
      ),
      bodyLarge: const TextStyle(fontSize: 16),
      bodyMedium: const TextStyle(fontSize: 15),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: const TextStyle(color: Color(0xFF6B7B80)),
      border: OutlineInputBorder(
        borderRadius: radioCampo,
        borderSide: const BorderSide(color: Color(0xFFC9D5D3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radioCampo,
        borderSide: const BorderSide(color: Color(0xFFC9D5D3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radioCampo,
        borderSide: const BorderSide(color: Ipesa.turquesa, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radioCampo,
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Ipesa.petroleo,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: Ipesa.fuenteTitulos,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Ipesa.petroleo,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Ipesa.borde),
        textStyle: const TextStyle(
          fontFamily: Ipesa.fuenteTitulos,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Ipesa.petroleo,
        textStyle: const TextStyle(
          fontFamily: Ipesa.fuenteTexto,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Ipesa.petroleo,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(
        fontFamily: Ipesa.fuenteTitulos,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ipesa.radio),
      ),
      margin: EdgeInsets.zero,
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ipesa.radio),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: const BorderSide(color: Ipesa.borde),
      backgroundColor: Colors.white,
      selectedColor: Ipesa.menta,
      labelStyle: const TextStyle(
        fontFamily: Ipesa.fuenteTexto,
        color: Ipesa.texto,
        fontWeight: FontWeight.w600,
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Ipesa.turquesa : null,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Ipesa.menta,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: Ipesa.fuenteTexto,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),

    dividerTheme: const DividerThemeData(color: Ipesa.borde, space: 32),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ipesa.texto,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
