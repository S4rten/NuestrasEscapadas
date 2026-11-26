import SwiftUI
import MapKit
import CoreLocation

// ============================================================================
// MAPA DEL DÍA (pestaña Plan): los planes del día como puntos numerados en
// orden, unidos por una línea, para ver si el recorrido tiene sentido.
// Cada plan se sitúa solo buscando su nombre cerca del destino; la posición
// se guarda en la nube para no tener que buscarla otra vez en ningún iPhone.
// ============================================================================

private struct PuntoDia: Identifiable {
    let id: String
    let numero: Int
    let nombre: String
    let coordenada: CLLocationCoordinate2D
    let completada: Bool
}

struct SeccionMapaDia: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada
    let dia: Int

    private var puntos: [PuntoDia] {
        var lista: [PuntoDia] = []
        for a in UbicadorPlanes.ordenadas(almacen: almacen, escapada: escapada, dia: dia) {
            guard let lat = a.latitud, let lon = a.longitud else { continue }
            lista.append(PuntoDia(
                id: a.id,
                numero: lista.count + 1,
                nombre: a.nombreSitio,
                coordenada: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                completada: a.completada
            ))
        }
        return lista
    }

    var body: some View {
        let puntos = self.puntos

        if !puntos.isEmpty {
                Section {
                    Map(initialPosition: .automatic) {
                        if puntos.count > 1 {
                            MapPolyline(coordinates: puntos.map { $0.coordenada })
                                .stroke(Color.accentColor.opacity(0.7), lineWidth: 3)
                        }
                        ForEach(puntos) { p in
                            Annotation(p.nombre, coordinate: p.coordenada) {
                                Text("\(p.numero)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(p.completada ? Color.green : Color.accentColor)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .id(puntos.map { $0.id }.joined())   // recoloca el mapa al cambiar de día
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Mapa del día \(dia)")
                } footer: {
                    Text("Los números siguen el orden del plan. Si un sitio sale mal, mantén pulsado el plan y elige «Quitar del mapa».")
                }
        }
    }
}

/// Sitúa los planes en el mapa buscando su nombre en Apple Maps.
@MainActor
enum UbicadorPlanes {
    /// Planes del día en el mismo orden que la línea del tiempo.
    static func ordenadas(almacen: Almacen, escapada: Escapada, dia: Int) -> [Actividad] {
        almacen.actividadesDe(escapada.id)
            .filter { $0.dia == dia }
            .sorted { a, b in
                if a.todoElDia != b.todoElDia { return a.todoElDia }
                switch (a.hora, b.hora) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.nombreSitio < b.nombreSitio
                }
            }
    }

    static func sinBuscar(almacen: Almacen, escapada: Escapada, dia: Int) -> [Actividad] {
        ordenadas(almacen: almacen, escapada: escapada, dia: dia)
            .filter { !$0.ubicacionBuscada && $0.latitud == nil }
    }

    /// Busca los planes del día que aún no tienen posición y la guarda en la nube.
    static func situar(almacen: Almacen, escapada: Escapada, dia: Int) async {
        let pendientes = sinBuscar(almacen: almacen, escapada: escapada, dia: dia)
        guard !pendientes.isEmpty else { return }

        let centro: CLLocationCoordinate2D? = {
            guard let lat = escapada.latitud, let lon = escapada.longitud else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }()

        for a in pendientes.prefix(10) {
            if Task.isCancelled { return }
            let peticion = MKLocalSearch.Request()
            if let centro = centro {
                peticion.naturalLanguageQuery = a.nombreSitio
                peticion.region = MKCoordinateRegion(center: centro, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
            } else {
                peticion.naturalLanguageQuery = "\(a.nombreSitio), \(escapada.destino)"
            }

            var campos: [String: Any] = ["ubicacionBuscada": true]
            if let item = try? await MKLocalSearch(request: peticion).start().mapItems.first {
                let c = item.placemark.coordinate
                // Si sale a más de 100 km del destino, seguramente es otro sitio con el mismo nombre.
                let lejos: Bool = {
                    guard let centro = centro else { return false }
                    let d = CLLocation(latitude: c.latitude, longitude: c.longitude)
                        .distance(from: CLLocation(latitude: centro.latitude, longitude: centro.longitude))
                    return d > 100_000
                }()
                if !lejos {
                    campos["latitud"] = c.latitude
                    campos["longitud"] = c.longitude
                }
            }
            almacen.actualizar(a.id, en: .actividades, campos: campos)
        }
    }
}
