import SwiftUI
import PhotosUI
import UIKit

// ============================================================================
// BILLETES A MANO: fotos o capturas de tarjetas de embarque, QR de entradas,
// confirmaciones… guardadas dentro de cada reserva. Una vez vistas con
// conexión, quedan guardadas en el iPhone y se pueden enseñar sin cobertura.
// ============================================================================

/// Botón pequeño bajo cada reserva: "🎫 Billetes (2)".
struct BotonBilletes: View {
    @EnvironmentObject var almacen: Almacen
    let reservaId: String
    let titulo: String
    @Binding var hoja: HojaDetalle?

    var body: some View {
        let cuantos = almacen.billetesDe(reserva: reservaId).count
        Button {
            hoja = .billetes(reservaId: reservaId, titulo: titulo)
        } label: {
            Label(cuantos == 0 ? "Añadir billete o QR" : "Billetes (\(cuantos))",
                  systemImage: cuantos == 0 ? "ticket" : "ticket.fill")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(cuantos == 0 ? Color.gray : Color.accentColor)
    }
}

struct BilletesView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada
    let reservaId: String
    let titulo: String

    @State private var seleccion: PhotosPickerItem? = nil
    @State private var mostrandoCamara = false
    @State private var procesando = false
    @State private var fotoNoValida = false
    @State private var abierto: Billete? = nil
    @State private var borrando: Billete? = nil
    @State private var mensajeTarjeta: String? = nil
    @State private var leyendoTarjetas = false

    private var camaraDisponible: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Si la reserva es un vuelo, las tarjetas de embarque se leen solas.
    private var vuelo: Vuelo? {
        almacen.vuelos.first { $0.id == reservaId }
    }

    var body: some View {
        let lista = almacen.billetesDe(reserva: reservaId)

        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $seleccion, matching: .images) {
                        Label("Elegir de la galería o una captura", systemImage: "photo.on.rectangle")
                    }
                    if camaraDisponible {
                        Button {
                            mostrandoCamara = true
                        } label: {
                            Label("Hacer foto al billete", systemImage: "camera.fill")
                        }
                    }
                    if procesando {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Guardando…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let mensaje = mensajeTarjeta {
                        Text(mensaje)
                            .font(.caption)
                            .foregroundStyle(mensaje.contains("⚠️") ? Color.orange : Color.green)
                    }
                    if vuelo != nil && !lista.isEmpty {
                        Button {
                            Task { await leerGuardadas(lista) }
                        } label: {
                            HStack {
                                Label("Leer las tarjetas de embarque guardadas", systemImage: "barcode.viewfinder")
                                Spacer()
                                if leyendoTarjetas { ProgressView() }
                            }
                        }
                        .disabled(leyendoTarjetas)
                    }
                } footer: {
                    Text(vuelo != nil
                         ? "Consejo: haz una captura de la tarjeta de embarque y elígela aquí. Su código se lee solo (en el iPhone, sin internet) y completa el vuelo, el localizador y el asiento."
                         : "Consejo: haz una captura de pantalla de la tarjeta de embarque o del QR y elígela aquí.")
                }

                Section {
                    if lista.isEmpty {
                        Text("Todavía no hay billetes guardados en esta reserva.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                            ForEach(lista) { b in
                                MiniaturaBillete(billete: b)
                                    .onTapGesture { abierto = b }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            borrando = b
                                        } label: {
                                            Label("Borrar", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Guardados (\(lista.count))")
                } footer: {
                    if !lista.isEmpty {
                        Text("Toca uno para verlo a pantalla completa (el brillo sube al máximo para que lean bien el QR). Mantén pulsado para borrarlo.")
                    }
                }
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .onAppear {
                // Se descargan todos al abrir: así quedan guardados para usarlos sin conexión.
                for b in lista { almacen.cargarBillete(b) }
            }
            .onChange(of: seleccion) { _, item in
                guard let item = item else { return }
                procesando = true
                Task {
                    let datos = await CompresorFotos.datos(de: item)
                    procesando = false
                    seleccion = nil
                    if let datos = datos {
                        anadirBillete(datos, original: nil)
                    } else {
                        fotoNoValida = true
                    }
                }
            }
            .fullScreenCover(isPresented: $mostrandoCamara) {
                SelectorCamara(
                    alHacerFoto: { imagen in
                        if let datos = CompresorFotos.comprimir(imagen) {
                            anadirBillete(datos, original: imagen)
                        } else {
                            fotoNoValida = true
                        }
                        mostrandoCamara = false
                    },
                    alCancelar: { mostrandoCamara = false },
                    frontal: false
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $abierto) { b in
                VisorBillete(billete: b)
            }
            .alert("No se pudo usar esa imagen", isPresented: $fotoNoValida) {
                Button("Vale", role: .cancel) {}
            } message: {
                Text("Prueba con otra imagen o con una captura de pantalla.")
            }
            .confirmationDialog("¿Borrar este billete?", isPresented: Binding(
                get: { borrando != nil },
                set: { if !$0 { borrando = nil } }
            ), titleVisibility: .visible) {
                Button("Borrar para los dos", role: .destructive) {
                    if let b = borrando { almacen.borrarBillete(b) }
                    borrando = nil
                }
                Button("Cancelar", role: .cancel) { borrando = nil }
            }
        }
    }

    private func guardar(_ datos: Data, tituloLeido: String? = nil) {
        let numero = almacen.billetesDe(reserva: reservaId).count + 1
        almacen.guardarBillete(
            datos,
            reservaId: reservaId,
            escapadaId: escapada.id,
            titulo: tituloLeido ?? "\(titulo) · \(numero)",
            miId: sesion.miId
        )
    }

    /// Guarda el billete y, si es de un vuelo, lee la tarjeta de embarque para completar el vuelo.
    private func anadirBillete(_ datos: Data, original: UIImage?) {
        guard let v = vuelo else {
            guardar(datos)
            return
        }
        procesando = true
        Task {
            var tarjeta: TarjetaEmbarque? = nil
            if let imagen = original ?? UIImage(data: datos) {
                tarjeta = await LectorTarjetaEmbarque.leer(imagen)
            }
            procesando = false
            if let t = tarjeta {
                let quien = t.nombrePila.isEmpty ? "" : " · \(t.nombrePila)"
                let asiento = t.asiento.isEmpty ? "" : " · \(t.asiento)"
                guardar(datos, tituloLeido: "Tarjeta de embarque\(quien)\(asiento)")
                mensajeTarjeta = almacen.aplicarTarjetas([t], aVuelo: v)
            } else {
                guardar(datos)
            }
        }
    }

    /// Lee las tarjetas que ya estaban guardadas (descargadas en el iPhone).
    private func leerGuardadas(_ lista: [Billete]) async {
        guard let v = vuelo else { return }
        leyendoTarjetas = true
        var tarjetas: [TarjetaEmbarque] = []
        for b in lista {
            guard let datos = almacen.billetesDescargados[b.id], let imagen = UIImage(data: datos) else { continue }
            if let t = await LectorTarjetaEmbarque.leer(imagen), !tarjetas.contains(t) {
                tarjetas.append(t)
            }
        }
        leyendoTarjetas = false
        mensajeTarjeta = tarjetas.isEmpty
            ? "No he encontrado ningún código de tarjeta de embarque en los billetes guardados (si alguno no se ha descargado aún, espera un momento)."
            : almacen.aplicarTarjetas(tarjetas, aVuelo: v)
    }
}

struct MiniaturaBillete: View {
    @EnvironmentObject var almacen: Almacen
    let billete: Billete

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
            if let datos = almacen.billetesDescargados[billete.id], let imagen = UIImage(data: datos) {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { almacen.cargarBillete(billete) }
    }
}

/// Pantalla completa con zoom y el brillo al máximo (para escanear el QR).
struct VisorBillete: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss
    let billete: Billete

    @State private var escala: CGFloat = 1
    @State private var escalaBase: CGFloat = 1
    @State private var brilloAnterior: CGFloat? = nil

    private var pantalla: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                if let datos = almacen.billetesDescargados[billete.id], let imagen = UIImage(data: datos) {
                    Image(uiImage: imagen)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(escala)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { valor in escala = min(max(escalaBase * valor, 1), 5) }
                                .onEnded { _ in escalaBase = escala }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                escala = escala > 1 ? 1 : 2.5
                                escalaBase = escala
                            }
                        }
                } else {
                    ProgressView("Cargando…")
                        .tint(.black)
                        .foregroundStyle(.black)
                }
            }
            .navigationTitle(billete.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if let datos = almacen.billetesDescargados[billete.id], let imagen = UIImage(data: datos) {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: Image(uiImage: imagen), preview: SharePreview(billete.titulo, image: Image(uiImage: imagen)))
                    }
                }
            }
        }
        .onAppear {
            almacen.cargarBillete(billete)
            if let p = pantalla {
                brilloAnterior = p.brightness
                p.brightness = 1
            }
        }
        .onDisappear {
            if let p = pantalla, let anterior = brilloAnterior {
                p.brightness = anterior
            }
        }
    }
}
