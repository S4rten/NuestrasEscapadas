# Nuestras Escapadas

App de iPhone (SwiftUI, iOS 17+) para planear y recordar las escapadas en pareja. Cada iPhone tiene un ID único y todo se sincroniza en tiempo real con Firebase Firestore.

## Estructura del repositorio

```
.github/workflows/build-ios.yml   <- compilación automática (GitHub Actions)
Sources/                          <- todo el código Swift (.swift)
GoogleService-Info.plist          <- el tuyo, descargado de Firebase (en la raíz)
project.yml                       <- definición del proyecto (XcodeGen)
firestore.rules                   <- reglas de seguridad de Firestore
.gitignore
README.md
```

## 1. Configurar Firebase (una sola vez)

1. En la consola de Firebase, abre tu proyecto y entra en **Firestore Database**. Si no existe, pulsa *Crear base de datos* (modo producción, la región más cercana).
2. En **Firestore → Reglas**, pega el contenido de `firestore.rules` y pulsa *Publicar*.
3. En *Configuración del proyecto → Tus apps → iOS*, comprueba que el **Bundle ID** es `com.pareja.nuestrasescapadas` y descarga `GoogleService-Info.plist`.
4. Sube ese archivo a la **raíz** del repositorio (junto a `project.yml`).
5. Recomendado: en Google Cloud → *Credenciales*, restringe la clave de API de iOS al Bundle ID anterior, y mantén el repositorio **privado**.

## 2. Compilar en GitHub

1. Sube todo el contenido de esta carpeta al repositorio (respetando la estructura de arriba).
2. En la pestaña **Actions**, ejecuta *Build iOS* (o haz un push). Tarda unos minutos.
3. Al terminar, descarga el artefacto `NuestrasEscapadas.ipa` (se conserva 14 días).

El `.ipa` sale **sin firmar**. Para instalarlo en tu iPhone hay que firmarlo con tu Apple ID, por ejemplo con Sideloadly. Con un Apple ID gratuito la app caduca a los 7 días y hay que reinstalarla.

## 3. Primer uso

1. En el primer iPhone: escribe tu nombre y pulsa **Crear espacio nuevo**. Se genera un código tipo `K7QM-X2PD-9TRW`.
2. En *Ajustes* (toca tu nombre arriba a la izquierda) comparte el código con tu pareja.
3. En el segundo iPhone: escribe su nombre, elige **Tengo un código** y pega el código.
4. Cada iPhone guarda su propio ID único; los gastos y tareas se asignan por ese ID, no por nombre.

Si reinstalas la app, entra con el mismo código y elige tu nombre de la lista para recuperar tu identidad.

## Cosas que conviene saber

- **Modo sorpresa**: oculta el destino y el plan en la app de la otra persona, pero es un ocultamiento solo de la interfaz. Los datos siguen siendo legibles en Firestore para quien tenga el código.
- **Seguridad**: las reglas se basan en que el código del espacio es largo y secreto. No hay inicio de sesión de usuarios. Para algo más estricto habría que añadir Firebase Authentication.
- **Divisas**: las tasas vienen de `open.er-api.com` y son orientativas; se pueden corregir a mano en cada gasto.
- **Sugerencia de vuelo**: usa el servicio gratuito adsbdb y puede no conocer todos los vuelos; siempre puedes rellenar a mano.
- **Notificaciones**: esta versión no incluye avisos push.
