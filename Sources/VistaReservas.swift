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
                VStack(alignment: .leading, spacing: 8) {
                    TarjetaVuelo(vuelo: vuelo)
                    BotonBilletes(reservaId: vuelo.id, titulo: "Vuelo \(vuelo.origen) → \(vuelo.destino)", hoja: $hoja)
                }
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .vuelo(vuelo) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrarReserva(id: vuelo.id, de: .vuelos)
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
                VStack(alignment: .leading, spacing: 8) {
                    TarjetaTren(tren: tren)
                    BotonBilletes(reservaId: tren.id, titulo: "Tren \(tren.estacionOrigen) → \(tren.estacionDestino)", hoja: $hoja)
                }
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .tren(tren) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrarReserva(id: tren.id, de: .trenes)
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
                VStack(alignment: .leading, spacing: 8) {
                    TarjetaAlojamiento(alojamiento: alojamiento, destino: escapada.destino)
                    // En el alojamiento ya no se añaden billetes; solo se ven los que ya estaban guardados.
                    if !almacen.billetesDe(reserva: alojamiento.id).isEmpty {
                        BotonBilletes(reservaId: alojamiento.id, titulo: alojamiento.nombre.isEmpty ? "Alojamiento" : alojamiento.nombre, hoja: $hoja)
                    }
                }
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .alojamiento(alojamiento) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrarReserva(id: alojamiento.id, de: .alojamientos)
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
            Text("Toca una reserva para editarla y desliza para borrarla. En los vuelos y trenes, «Billetes» guarda la tarjeta de embarque o el QR como foto.")
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
                Text(vuelo.diaSalidaLocal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(vuelo.origen)
                        .font(.title2.bold())
                    if !vuelo.ciudadOrigen.isEmpty {
                        Text(vuelo.ciudadOrigen)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(vuelo.horaSalidaLocal)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane")
                        .foregroundStyle(Color.accentColor)
                    if let minutos = vuelo.minutosDeVuelo {
                        Text(textoDuracion(minutos))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(vuelo.destino)
                        .font(.title2.bold())
                    if !vuelo.ciudadDestino.isEmpty {
                        Text(vuelo.ciudadDestino)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(vuelo.horaLlegadaLocal)
                        .font(.caption.bold())
                }
            }

            if vuelo.tieneHoraLocalDistinta {
                HStack {
                    Text("🕐 Horas locales de cada aeropuerto")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if !vuelo.terminalPuerta.isEmpty || !vuelo.asiento.isEmpty {
                HStack(spacing: 12) {
                    if !vuelo.terminalPuerta.isEmpty {
                        Label(vuelo.terminalPuerta, systemImage: "door.left.hand.open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !vuelo.asiento.isEmpty {
                        Text("💺 \(vuelo.asiento)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            // El mismo día del vuelo: retrasos, puerta y cinta (con la clave de horarios).
            FilaEstadoVuelo(vuelo: vuelo)

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
