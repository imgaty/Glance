//
//  BackdropMesh.swift
//  Glance
//
//  Created by Gaty on 10/11/2026.
//

import simd

enum BackdropMesh {
    struct Mesh {
        var vertices: [ArtworkBackdrop.Vertex]
        var indices: [UInt32]
    }
    private struct Edge: Hashable {
        let a: Int
        let b: Int
        init(_ a: Int, _ b: Int) {
            self.a = min(a, b)
            self.b = max(a, b)
        }
    }

    /// A six by six control grid, three subdivision steps, and a fixed outer corner.
    /// UVs undergo the same subdivision as the two endpoint surfaces.
    static func make(variant: Int) -> Mesh {
        let coordinates = controls[min(max(variant, 0), controls.count - 1)]
        let grid: [Float] = [0, 0.15, 0.3, 0.4, 0.6, 1]
        var surfaces = (0..<2).map { endpoint in
            (0..<36).map { i in SIMD4<Float>(grid[i % 6], grid[i / 6], coordinates[endpoint * 72 + i * 2] * 2 - 1, coordinates[endpoint * 72 + i * 2 + 1] * 2 - 1) }
        }
        var faces = (0..<25).map { i -> [Int] in
            let v = (i / 5) * 6 + i % 5
            return [v, v + 1, v + 7, v + 6]
        }
        for _ in 0..<3 {
            let first = subdivide(surfaces[0], faces)
            let second = subdivide(surfaces[1], faces)
            surfaces = [first.vertices, second.vertices]
            faces = first.faces
        }
        let vertices = zip(surfaces[0], surfaces[1]).map {
            ArtworkBackdrop.Vertex(uv: SIMD2($0.x, $0.y), from: SIMD2($0.z, $0.w), to: SIMD2($1.z, $1.w))
        }
        let indices = faces.flatMap { f in [f[0], f[1], f[2], f[2], f[3], f[0]].map(UInt32.init) }
        return Mesh(vertices: vertices, indices: indices)
    }

    private static func subdivide(_ vertices: [SIMD4<Float>], _ faces: [[Int]]) -> (vertices: [SIMD4<Float>], faces: [[Int]]) {
        func mean(_ values: [SIMD4<Float>]) -> SIMD4<Float> { values.reduce(.zero, +) / Float(values.count) }
        let centers = faces.map { mean($0.map { vertices[$0] }) }
        var adjacent = [[Int]](repeating: [], count: vertices.count)
        var neighbors = [[Int]](repeating: [], count: vertices.count)
        var edgeFaces: [Edge: [Int]] = [:]
        var edges: [Edge] = []
        for (j, face) in faces.enumerated() {
            for (i, a) in face.enumerated() {
                let edge = Edge(a, face[(i + 1) % 4])
                if edgeFaces[edge] == nil { edges.append(edge) }
                edgeFaces[edge, default: []].append(j)
                adjacent[a].append(j)
            }
        }
        for edge in edges {
            neighbors[edge.a].append(edge.b)
            neighbors[edge.b].append(edge.a)
        }
        var result = vertices.enumerated().map { i, p -> SIMD4<Float> in
            // The four original corners stay on the texture boundary.
            if adjacent[i].count == 1 { return p }
            let boundary = neighbors[i].filter { edgeFaces[Edge(i, $0)]!.count == 1 }
            if boundary.count == 2 { return (6 * p + vertices[boundary[0]] + vertices[boundary[1]]) / 8 }
            let faceMean = mean(adjacent[i].map { centers[$0] })
            let edgeMean = mean(neighbors[i].map { (p + vertices[$0]) / 2 })
            let n = Float(adjacent[i].count)
            return (faceMean + 2 * edgeMean + (n - 3) * p) / n
        }
        var edgeIndices: [Edge: Int] = [:]
        for edge in edges {
            edgeIndices[edge] = result.count
            let touching = edgeFaces[edge]!
            result.append(mean([vertices[edge.a], vertices[edge.b]] + (touching.count == 2 ? touching.map { centers[$0] } : [])))
        }
        let centerOffset = result.count
        result += centers
        var divided: [[Int]] = []
        for (j, face) in faces.enumerated() {
            for (i, a) in face.enumerated() {
                divided.append([a, edgeIndices[Edge(a, face[(i + 1) % 4])]!, centerOffset + j, edgeIndices[Edge(a, face[(i + 3) % 4])]!])
            }
        }
        return (result, divided)
    }

    // Normalized endpoint coordinates, in five variants. The regular border stays fixed;
    // only the inner control points bend the artwork.
    static let controls: [[Float]] = [
        [
            0, 0, 0.2, 0, 0.4, 0, 0.6, 0, 0.8, 0, 1, 0,
            0, 0.2, -0.0933, 0.4, 0.4, 0.2, 0.6, 0.2, 0.3653, 0.1335, 1, 0.2,
            0, 0.4, 0.4232, 0.359, 0.3429, 0.5349, 0.6, 0.4, 0.832, 0.4148, 1, 0.4,
            0, 0.6, 0.2, 0.6, 0.2293, 0.7775, 0.7829, 0.5595, 0.6514, 0.7302, 1, 0.6,
            0, 0.8, 0.2, 0.8, 0.28, 0.9195, 0.4773, 0.8, 0.8, 0.8, 1, 0.8,
            0, 1, 0.6514, 1.1073, 0.4, 1, 1, 1.0317, 1, 1.1302, 1, 1,
            0, 0, 0.2, 0, 0.4, 0, 0.6, 0, 0.8, 0, 1, 0,
            0, 0.2, -0.0933, 0.4, 0.4, 0.2, 0.6, 0.2, 0.8587, 0.2234, 1, 0.2,
            0, 0.4, 0.4526, 0.6053, 0.3429, 0.5349, 0.6, 0.4, 0.832, 0.4148, 1, 0.4,
            0, 0.6, 0.2, 0.6, 0.2293, 0.7775, 0.7829, 0.5595, 0.6514, 0.7302, 1, 0.6,
            0, 0.8, 0.2, 0.8, 0.28, 0.9195, 0.4773, 0.8, 0.8, 0.8, 1, 0.8,
            0, 1, 0.6514, 1.1073, 0.4, 1, 1, 1.0317, 1, 1.1302, 1, 1,
        ],
        [
            0, 0, 0.2, 0, 0.4, 0, 0.6, 0, 0.8, 0, 1, 0,
            0, 0.2, 0.3265, 0.3839, 0.4, 0.2, 0.462, 0.3424, 0.683, 0.2797, 1, 0.2,
            0, 0.4, 0.2, 0.4, 0.4, 0.4, 0.6, 0.4903, 0.6574, 0.4903, 1.1357, 0.4,
            -0.1173, 0.4597, 0.3771, 0.4384, 0.6415, 0.5947, 0.8254, 0.6935, 0.9334, 0.5862, 1, 0.6,
            -0.0437, 0.6533, 0.2, 0.6618, 0.683, 0.7362, 0.8139, 0.833, 0.9104, 0.8085, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
            0, 0, 0.2, 0, 0.4, 0, 0.6, 0, 0.8, 0, 1, 0,
            0, 0.2, 0.2437, 0.4392, 0.4, 0.2, 0.462, 0.3424, 0.683, 0.2797, 1, 0.2,
            0, 0.4, 0.1494, 0.4787, 0.4, 0.5063, 0.6966, 0.516, 0.8139, 0.4478, 1.1357, 0.4,
            -0.1173, 0.4597, 0.2437, 0.6085, 0.6414, 0.5756, 0.8254, 0.6935, 0.9334, 0.5862, 1, 0.6,
            -0.0437, 0.6533, 0.2, 0.6618, 0.683, 0.7362, 0.8139, 0.833, 0.9104, 0.8085, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
        ],
        [
            0, 0, 0.2, 0, 0.4, 0, 0.7465, -0.0935, 0.9702, -0.0872, 1.5935, -0.0308,
            -0.1675, 0.2878, 0.7185, 0.3087, 0.5952, 0.0728, 0.7823, 0.0815, 0.9318, 0.301, 1.1369, 0.3756,
            0, 0.4, 0.3295, 0.4607, 0.7823, 0.3087, 0.7465, 0.365, 0.9514, 0.4305, 1.1514, 0.4424,
            0, 0.6, 0.2, 0.6, 0.3295, 0.4424, 0.5703, 0.5, 0.7887, 0.4847, 1, 0.6,
            0, 0.8, 0.2414, 0.7926, 0.0418, 0.7303, 0.5952, 0.4688, 0.9433, 0.6929, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
            0, 0, 0.2, 0, 0.4, 0, 0.7465, -0.0935, 0.9702, -0.0872, 1.5935, -0.0308,
            -0.1675, 0.2878, 0.5414, 0.2825, 0.5952, 0.0728, 0.7823, 0.0815, 0.9318, 0.301, 1.1369, 0.3756,
            0, 0.4, 0.2881, 0.4479, 0.7823, 0.3087, 0.8363, 0.3661, 0.9514, 0.4305, 1.1514, 0.4424,
            0, 0.6, 0.177, 0.6, 0.4, 0.4775, 0.5703, 0.5, 0.7887, 0.4847, 1, 0.6,
            0, 0.8, 0.2414, 0.7926, 0.1499, 0.7324, 0.5952, 0.5623, 0.9433, 0.6929, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
        ],
        [
            0, 0, 0.2, 0, 0.4, 0, 0.7465, -0.0935, 0.9702, -0.0872, 1.5935, -0.0308,
            -0.1675, 0.2878, 0.7185, 0.3087, 0.5952, 0.0728, 0.7823, 0.0815, 0.9318, 0.301, 1.1369, 0.3756,
            0, 0.4, 0.3295, 0.4607, 0.7823, 0.3087, 0.7465, 0.365, 0.9514, 0.4305, 1.1514, 0.4424,
            0, 0.6, 0.2, 0.6, 0.3295, 0.4424, 0.5703, 0.5, 0.7887, 0.4847, 1, 0.6,
            0, 0.8, 0.2414, 0.7926, 0.0418, 0.7303, 0.5952, 0.4688, 0.9433, 0.6929, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
            0, 0, 0.2, 0, 0.4, 0, 0.7465, -0.0935, 0.9702, -0.0872, 1.5935, -0.0308,
            -0.1675, 0.2878, 0.5414, 0.2825, 0.5952, 0.0728, 0.7823, 0.0815, 0.9318, 0.301, 1.1369, 0.3756,
            0, 0.4, 0.2881, 0.4479, 0.7823, 0.3087, 0.8363, 0.3661, 0.9514, 0.4305, 1.1514, 0.4424,
            0, 0.6, 0.177, 0.6, 0.4, 0.4775, 0.5703, 0.5, 0.7887, 0.4847, 1, 0.6,
            0, 0.8, 0.2414, 0.7926, 0.1499, 0.7324, 0.5952, 0.5623, 0.9433, 0.6929, 1, 0.8,
            0, 1, 0.2, 1, 0.4, 1, 0.6, 1, 0.8, 1, 1, 1,
        ],
        [
            -0.2351, -0.0967, 0.2135, -0.1414, 0.9221, -0.0908, 0.9221, -0.0685, 1.3027, 0.0253, 1.2351, 0.1786,
            -0.3768, 0.1851, 0.2, 0.2, 0.6615, 0.3146, 0.9543, 0, 0.6969, 0.1911, 1, 0.2,
            0, 0.4, 0.2, 0.4, 0.0776, 0.2318, 0.6, 0.4, 0.6615, 0.3851, 1, 0.4,
            0, 0.6, 0.1291, 0.6, 0.4, 0.6, 0.4, 0.4304, 0.4264, 0.5792, 1.2029, 0.8188,
            -0.1192, 1, 0.6, 0.8, 0.4264, 0.8104, 0.6, 0.8, 0.8, 0.8, 1, 0.8,
            0, 1, 0.0776, 1.0283, 0.4, 1, 0.6, 1, 0.8, 1, 1.1868, 1.0283,
            -0.2351, -0.0967, 0.2135, -0.1414, 0.9221, -0.0908, 0.9221, -0.0685, 1.3027, 0.0253, 1.2351, 0.1786,
            -0.3768, 0.1851, 0.1839, 0.2, 0.7034, 0.2952, 0.9543, 0, 0.7775, 0.3339, 1, 0.2,
            0, 0.4, 0.0357, 0.5369, 0.0776, 0.2318, 0.6, 0.4, 0.6615, 0.3851, 1, 0.4,
            0, 0.6, 0.2, 0.6878, 0.4, 0.6, 0.5, 0.5896, 0.6454, 0.6878, 1.2029, 0.8188,
            -0.1192, 1, 0.6193, 0.9027, 0.4264, 0.8104, 0.6, 0.8, 0.8, 0.8, 1, 0.8,
            0, 1, 0.0776, 1.0283, 0.4, 1, 0.6, 1, 0.8, 1, 1.1868, 1.0283,
        ],
    ]
}
