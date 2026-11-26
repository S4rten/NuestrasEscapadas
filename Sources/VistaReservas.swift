import SwiftUI

// ============================================================================
// PESTAÑA RESERVAS: vuelos, trenes y alojamientos
// ============================================================================

struct ReservasSecciones: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada
    @Binding var hoja: HojaDetalle?

    var body: some View {
        // Vuelos
        Section {
            ForEach(almacen.vuelosDe(escapada.id)) { vuelo in
                TarjetaVuelo(vuelo: vuelo)
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .vuelo(vuelo) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: vuelo.id, de: .vuelos)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
            Button {
                hoja = .vuelo(nil)
            } label: {
                Label("Añadir vuelo", systemImage: "airplane.circle.fill")
            }
        } header: {
            Text("Vuelos")
        }

        // Trenes
        Section {
            ForEach(almacen.trenesDe(escapada.id)) { tren in
                TarjetaTren(tren: tren)
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .tren(tren) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: tren.id, de: .trenes)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
            Button {
                hoja = .tren(nil)
            } label: {
                Label("Añadir billete de tren", systemImage: "tram.circle.fill")
            }
        } header: {
            Text("Trenes")
        }

        // Alojamientos
        Section {
            ForEach(almacen.alojamientosDe(escapada.id)) { alojamiento in
                TarjetaAlojamiento(alojamiento: alojamiento, destino: escapada.destino)
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .alojamiento(alojamiento) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: alojamiento.id, de: .alojamientos)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
            Button {
                hoja = .alojamiento(nil)
            } label: {
                Label("Añadir hotel, apartamento o alojamiento", systemImage: "bed.double.fill")
            }
        } header: {
            Text("Alojamiento")
        } footer: {
            Text("Toca una reserva para editarla y desliza para borrarla.")
        }
    }
}

// ============================================================================
// TARJETAS
// ============================================================================

struct TarjetaVuelo: View {
    let vuelo: Vuelo

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Chip(texto: vuelo.trayecto.uppercased())
                Text([vuelo.aerolinea, vuelo.numeroVuelo].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vuelo.fechaHoraSalida.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(vuelo.origen)
                        .font(.title2.bold())
                    Text(vuelo.fechaHoraSalida.formatted(date: .omitted, time: .shortened))
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Image(systemName: "airplane")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(vuelo.destino)
                        .font(.title2.bold())
                    Text(vuelo.fechaHoraLlegada.formatted(date: .omitted, time: .shortened))
                        .font(.caption.bold())
                }
            }

            if !vuelo.terminalPuerta.isEmpty {
                HStack {
                    Label(vuelo.terminalPuerta, systemImage: "door.left.hand.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                if !vuelo.localizador.isEmpty {
                    BotonCopiar(etiqueta: "Loc", valor: vuelo.localizador)
                }
                Spacer()
                if let enlace = urlDesdeTexto(vuelo.urlReserva) {
                    BotonEnlace(titulo: "Check-in", url: enlace, icono: "arrow.up.right.square")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct TarjetaTren: View {
    let tren: TrenViaje

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Chip(texto: tren.trayecto.uppercased())
                Text("🚂 \(tren.operadora)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(tren.fechaHoraSalida.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(tren.estacionOrigen)
                        .font(.subheadline.bold())
                    Text(tren.fechaHoraSalida.formatted(date: .omitted, time: .shortened))
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Image(systemName: "tram.fill")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(tren.estacionDestino)
                        .font(.subheadline.bold())
                    Text(tren.fechaHoraLlegada.formatted(date: .omitted, time: .shortened))
                        .font(.caption.bold())
                }
            }

            HStack(spacing: 8) {
                if !tren.localizador.isEmpty {
                    BotonCopiar(etiqueta: "Loc", valor: tren.localizador)
                }
                Spacer()
                if let enlace = urlDesdeTexto(tren.urlReserva) {
                    BotonEnlace(titulo: "Billete", url: enlace, icono: "arrow.up.right.square")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct TarjetaAlojamiento: View {
    let alojamiento: Alojamiento
    let destino: String

    private var consultaMapa: String {
        alojamiento.direccion.isEmpty ? "\(alojamiento.nombre) \(destino)" : alojamiento.direccion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alojamiento.nombre.isEmpty ? "Alojamiento reservado" : alojamiento.nombre)
                    .font(.headline)
                if !alojamiento.direccion.isEmpty {
                    Text("📍 \(alojamiento.direccion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Entrada: \(alojamiento.entrada.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.down.right.circle")
                    .font(.caption.weight(.semibold))
                Label("Salida: \(alojamiento.salida.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.up.right.circle")
                    .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                if !alojamiento.codigoReserva.isEmpty {
                    BotonCopiar(etiqueta: "Ref", valor: alojamiento.codigoReserva)
                }
                if let mapa = urlMapa(consulta: consultaMapa),
                   !(alojamiento.nombre.isEmpty && alojamiento.direccion.isEmpty) {
                    BotonEnlace(titulo: "Cómo llegar", url: mapa, icono: "map.fill")
                }
                if let reserva = urlDesdeTexto(alojamiento.urlReserva) {
                    BotonEnlace(titulo: "Reserva", url: reserva)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
