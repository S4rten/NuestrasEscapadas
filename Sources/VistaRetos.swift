import SwiftUI
import PhotosUI
import UIKit

// ============================================================================
// PESTAÑA RETOS: retos de selfies y fotos durante el viaje.
// Los retos se pueden preparar antes de salir; las fotos se hacen desde el
// primer día del viaje (con la cámara o eligiéndolas de la galería).
// ============================================================================

struct RetosSecciones: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let escapada: Escapada
    @Binding var hoja: HojaDetalle?

    @State private var textoReto = ""
    @State private var mostrandoSugerencias = false

    var body: some View {
        let retos = almacen.retosDe(escapada.id)
        let hechos = retos.filter { $0.completado }.count

        SeccionRetoDelDia(escapada: escapada)

        Section {
            if !retos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(hechos), total: Double(retos.count))
                        .tint(hechos == retos.count ? Color.green : Color.accentColor)
                    Text(hechos == retos.count
                         ? "¡Todos los retos conseguidos! 🏆"
                         : "\(hechos) de \(retos.count) retos conseguidos")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                TextField("Nuevo reto (ej: selfie con un gato)", text: $textoReto)
                    .onSubmit { anadir(textoReto) }
                Button {
                    anadir(textoReto)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(textoReto.recortado.isEmpty)
            }

            // Cada vez que se abre salen 10 retos distintos (inventados y de sitios cercanos).
            Button {
                mostrandoSugerencias = true
            } label: {
                Label("Retos sugeridos (10 nuevos cada vez)", systemImage: "lightbulb.fill")
            }
            .sheet(isPresented: $mostrandoSugerencias) {
                SugerenciasRetosView(escapada: escapada)
            }

            ForEach(retos) { reto in
                FilaReto(reto: reto, puedeFotografiar: escapada.haEmpezado, hoja: $hoja)
            }
        } header: {
            HStack {
                Text("Retos de fotos")
                Spacer()
                if !retos.isEmpty {
                    Text("\(hechos)/\(retos.count)")
                        .font(.caption.bold())
                }
            }
        } footer: {
            if escapada.haEmpezado {
                Text("Toca la cámara para hacer la foto o la galería para elegir una. Toca un reto conseguido para ver su foto y desliza para borrarlo.")
            } else {
                Text("Preparad los retos ahora: las fotos se podrán hacer a partir del \(escapada.fechaInicio.formatted(date: .long, time: .omitted)).")
            }
        }
    }

    private func anadir(_ texto: String) {
        let t = texto.recortado
        guard !t.isEmpty else { return }
        var reto = Reto()
        reto.escapadaId = escapada.id
        reto.texto = t
        reto.creadoPorId = sesion.miId
        reto.creadoEn = Date()
        almacen.guardar(reto, en: .retos)
        if texto == textoReto { textoReto = "" }
    }
}

// ============================================================================
// FILA DE UN RETO
// ============================================================================

struct FilaReto: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let reto: Reto
    let puedeFotografiar: Bool
    @Binding var hoja: HojaDetalle?

    @State private var seleccion: PhotosPickerItem? = nil
    @State private var procesando = false
    @State private var fotoNoValida = false

    private var camaraDisponible: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        HStack(spacing: 12) {
            if reto.completado {
                MiniaturaReto(reto: reto, lado: 48)
            } else {
                Image(systemName: "camera.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(reto.texto)
                    .font(.subheadline.weight(.medium))
                Text(reto.completado
                     ? "✅ Conseguido por \(reto.completadoPorId == sesion.miId ? sesion.miNombre : almacen.nombre(de: reto.completadoPorId, miId: sesion.miId))"
                     : "Pendiente")
                    .font(.caption2)
                    .foregroundStyle(reto.completado ? Color.green : Color.secondary)
            }

            Spacer(minLength: 0)

            if !reto.completado && puedeFotografiar {
                if procesando {
                    ProgressView()
                } else {
                    if camaraDisponible {
                        Button {
                            hoja = .camaraReto(reto)
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                    PhotosPicker(selection: $seleccion, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if reto.completado { hoja = .fotoReto(reto) }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                almacen.borrarReto(reto)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .onChange(of: seleccion) { _, nuevo in
            guard let item = nuevo else { return }
            procesando = true
            Task {
                if let datos = await CompresorFotos.datos(de: item) {
                    almacen.guardarFoto(datos, para: reto, miId: sesion.miId)
                } else {
                    fotoNoValida = true
                }
                procesando = false
                seleccion = nil
            }
        }
        .alert("No se pudo usar esa foto", isPresented: $fotoNoValida) {
            Button("Vale", role: .cancel) {}
        } message: {
            Text("Prueba con otra imagen de la galería.")
        }
    }
}

/// Miniatura cuadrada de la foto de un reto (la descarga si hace falta).
struct MiniaturaReto: View {
    @EnvironmentObject var almacen: Almacen
    let reto: Reto
    let lado: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
            if let datos = almacen.fotosDescargadas[reto.claveFoto], let imagen = UIImage(data: datos) {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onAppear { almacen.cargarFoto(de: reto) }
        .onChange(of: reto.claveFoto) { _, _ in almacen.cargarFoto(de: reto) }
    }
}

// ============================================================================
// VISOR DE LA FOTO DE UN RETO (ver, compartir, cambiar o quitar)
// ============================================================================

struct VisorFotoReto: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let retoId: String

    @State private var seleccion: PhotosPickerItem? = nil
    @State private var procesando = false
    @State private var confirmandoQuitar = false
    @State private var fotoNoValida = false

    var body: some View {
        NavigationStack {
            Group {
                if let reto = almacen.reto(retoId) {
                    contenido(reto)
                } else {
                    ContentUnavailableView("Este reto ya no existe", systemImage: "camera")
                }
            }
            .navigationTitle("Reto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func textoAutor(_ reto: Reto) -> String {
        let quien = reto.completadoPorId == sesion.miId
            ? sesion.miNombre
            : almacen.nombre(de: reto.completadoPorId, miId: sesion.miId)
        var texto = "Conseguido por \(quien)"
        if let fecha = reto.fotoEn {
            texto += " · " + fecha.formatted(date: .abbreviated, time: .shortened)
        }
        return texto
    }

    @ViewBuilder
    private func contenido(_ reto: Reto) -> some View {
        let imagen = almacen.fotosDescargadas[reto.claveFoto].flatMap { UIImage(data: $0) }

        VStack(spacing: 16) {
            Group {
                if let imagen = imagen {
                    Image(uiImage: imagen)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if reto.completado {
                    ProgressView("Descargando foto…")
                } else {
                    ContentUnavailableView("Aún no hay foto", systemImage: "camera")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 4) {
                Text(reto.texto)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if reto.completado {
                    Text(textoAutor(reto))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if procesando {
                ProgressView("Subiendo foto…")
            } else {
                HStack(spacing: 12) {
                    if let imagen = imagen {
                        ShareLink(
                            item: Image(uiImage: imagen),
                            preview: SharePreview(reto.texto, image: Image(uiImage: imagen))
                        ) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }

                    PhotosPicker(selection: $seleccion, matching: .images) {
                        Label(reto.completado ? "Cambiar" : "Elegir foto", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if reto.completado {
                        Button(role: .destructive) {
                            confirmandoQuitar = true
                        } label: {
                            Label("Quitar", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .onAppear { almacen.cargarFoto(de: reto) }
        .onChange(of: reto.claveFoto) { _, _ in almacen.cargarFoto(de: reto) }
        .onChange(of: seleccion) { _, nuevo in
            guard let item = nuevo else { return }
            procesando = true
            Task {
                if let datos = await CompresorFotos.datos(de: item) {
                    almacen.guardarFoto(datos, para: reto, miId: sesion.miId)
                } else {
                    fotoNoValida = true
                }
                procesando = false
                seleccion = nil
            }
        }
        .confirmationDialog("¿Quitar la foto de este reto?", isPresented: $confirmandoQuitar, titleVisibility: .visible) {
            Button("Quitar foto", role: .destructive) {
                almacen.quitarFoto(de: reto)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El reto volverá a quedar pendiente en los dos iPhones.")
        }
        .alert("No se pudo usar esa foto", isPresented: $fotoNoValida) {
            Button("Vale", role: .cancel) {}
        } message: {
            Text("Prueba con otra imagen de la galería.")
        }
    }
}

// ============================================================================
// CÁMARA (abre la frontal para los selfies; se puede girar a la trasera)
// ============================================================================

struct CamaraReto: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let reto: Reto

    var body: some View {
        SelectorCamara(
            alHacerFoto: { imagen in
                if let datos = CompresorFotos.comprimir(imagen) {
                    almacen.guardarFoto(datos, para: reto, miId: sesion.miId)
                }
                dismiss()
            },
            alCancelar: { dismiss() }
        )
    }
}

struct SelectorCamara: UIViewControllerRepresentable {
    let alHacerFoto: (UIImage) -> Void
    let alCancelar: () -> Void
    /// Selfies con la frontal; billetes y documentos con la trasera.
    var frontal: Bool = true

    func makeCoordinator() -> Coordinador {
        Coordinador(alHacerFoto: alHacerFoto, alCancelar: alCancelar)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let selector = UIImagePickerController()
        selector.sourceType = .camera
        if frontal && UIImagePickerController.isCameraDeviceAvailable(.front) {
            selector.cameraDevice = .front
        }
        selector.delegate = context.coordinator
        return selector
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let alHacerFoto: (UIImage) -> Void
        let alCancelar: () -> Void

        init(alHacerFoto: @escaping (UIImage) -> Void, alCancelar: @escaping () -> Void) {
            self.alHacerFoto = alHacerFoto
            self.alCancelar = alCancelar
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let imagen = info[.originalImage] as? UIImage {
                alHacerFoto(imagen)
            } else {
                alCancelar()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            alCancelar()
        }
    }
}

// ============================================================================
// COMPRESIÓN: cada foto debe caber en un documento de Firestore (máx. 1 MB).
// ============================================================================

enum CompresorFotos {
    static let bytesMaximos = 750_000

    static func comprimir(_ imagen: UIImage) -> Data? {
        var lado: CGFloat = 1600
        while lado >= 600 {
            let reducida = redimensionar(imagen, ladoMaximo: lado)
            for calidad in [0.75, 0.6, 0.45, 0.3] as [CGFloat] {
                if let datos = reducida.jpegData(compressionQuality: calidad), datos.count <= bytesMaximos {
                    return datos
                }
            }
            lado -= 400
        }
        return nil
    }

    /// Lee una imagen de la galería y la deja lista para subir.
    @MainActor
    static func datos(de item: PhotosPickerItem) async -> Data? {
        guard let bruto = try? await item.loadTransferable(type: Data.self),
              let imagen = UIImage(data: bruto) else { return nil }
        return comprimir(imagen)
    }

    private static func redimensionar(_ imagen: UIImage, ladoMaximo: CGFloat) -> UIImage {
        let tamano = imagen.size
        let escala = min(1, ladoMaximo / max(tamano.width, tamano.height, 1))
        let nuevo = CGSize(width: floor(tamano.width * escala), height: floor(tamano.height * escala))
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        formato.opaque = true
        return UIGraphicsImageRenderer(size: nuevo, format: formato).image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: nuevo))
        }
    }
}
