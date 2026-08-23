import Foundation

/// A search hit not yet persisted — inserted as a FoodItem only when the user logs/saves it.
struct FoodSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let brand: String?
    let source: String // "openFoodFacts" | "usda" | "fndds"
    let barcode: String?
    var fdcId: String? = nil // 'let' with a default is excluded from Swift's memberwise init; 'var' keeps it settable
    let servingSize: Double
    let servingUnit: String
    let calories: Double // per serving
    let protein: Double
    let carbs: Double
    let fat: Double

    func toFoodItem() -> FoodItem {
        FoodItem(name: name, brand: brand, source: source, barcode: barcode, fdcId: fdcId,
                 servingSize: servingSize, servingUnit: servingUnit,
                 calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

enum FoodSearchService {
    static var usdaKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String) ?? ""
    }

    // MARK: Open Food Facts

    static func lookupBarcode(_ barcode: String) async throws -> FoodSearchResult? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        guard let p = decoded.product else { return nil }
        return offToResult(p, barcode: barcode)
    }

    static func searchOpenFoodFacts(_ query: String) async throws -> [FoodSearchResult] {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "15"),
            .init(name: "fields", value: "product_name,brands,code,nutriments,serving_quantity,serving_quantity_unit"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return decoded.products.compactMap { offToResult($0, barcode: $0.code) }
    }

    private static func offToResult(_ p: OFFProduct, barcode: String?) -> FoodSearchResult? {
        guard let name = p.product_name, !name.isEmpty, let n = p.nutriments else { return nil }
        // OFF nutriments are per 100g; use declared serving if present, else 100g.
        let servingSize = p.serving_quantity.flatMap(Double.init) ?? 100
        let servingUnit = p.serving_quantity_unit ?? "g"
        let factor = servingSize / 100.0
        guard let kcal100 = n.energyKcal100g else { return nil }
        return FoodSearchResult(
            name: name, brand: p.brands, source: "openFoodFacts", barcode: barcode,
            servingSize: servingSize, servingUnit: servingUnit,
            calories: kcal100 * factor,
            protein: (n.proteins_100g ?? 0) * factor,
            carbs: (n.carbohydrates_100g ?? 0) * factor,
            fat: (n.fat_100g ?? 0) * factor)
    }

    // MARK: USDA FoodData Central

    static func searchUSDA(_ query: String) async throws -> [FoodSearchResult] {
        guard !usdaKey.isEmpty, usdaKey != "REPLACE_ME" else { return [] }
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "pageSize", value: "15"),
            .init(name: "dataType", value: "Foundation,SR Legacy"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(usdaKey, forHTTPHeaderField: "X-Api-Key")
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return decoded.foods.compactMap { f in
            func nutrient(_ id: Int) -> Double {
                f.foodNutrients.first { $0.nutrientId == id }?.value ?? 0
            }
            let kcal = nutrient(1008)
            guard kcal > 0 else { return nil }
            // USDA values are per 100g.
            return FoodSearchResult(
                name: f.description, brand: nil, source: "usda", barcode: nil,
                servingSize: 100, servingUnit: "g",
                calories: kcal, protein: nutrient(1003), carbs: nutrient(1005), fat: nutrient(1004))
        }
    }

    /// Combined text search: both sources in parallel, failures tolerated per-source.
    static func search(_ query: String) async -> [FoodSearchResult] {
        async let off = (try? searchOpenFoodFacts(query)) ?? []
        async let usda = (try? searchUSDA(query)) ?? []
        return await usda + off // whole foods first, then branded
    }
}

// MARK: - Response shapes

private struct OFFProductResponse: Decodable { let product: OFFProduct? }
private struct OFFSearchResponse: Decodable { let products: [OFFProduct] }
private struct OFFProduct: Decodable {
    let product_name: String?
    let brands: String?
    let code: String?
    let serving_quantity: String?
    let serving_quantity_unit: String?
    let nutriments: OFFNutriments?

    private enum CodingKeys: String, CodingKey {
        case product_name, brands, code, serving_quantity, serving_quantity_unit, nutriments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        product_name = try? c.decode(String.self, forKey: .product_name)
        brands = try? c.decode(String.self, forKey: .brands)
        code = try? c.decode(String.self, forKey: .code)
        // serving_quantity is sometimes a number, sometimes a string
        if let s = try? c.decode(String.self, forKey: .serving_quantity) {
            serving_quantity = s
        } else if let d = try? c.decode(Double.self, forKey: .serving_quantity) {
            serving_quantity = String(d)
        } else {
            serving_quantity = nil
        }
        serving_quantity_unit = try? c.decode(String.self, forKey: .serving_quantity_unit)
        nutriments = try? c.decode(OFFNutriments.self, forKey: .nutriments)
    }
}
private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins_100g: Double?
    let carbohydrates_100g: Double?
    let fat_100g: Double?

    private enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins_100g, carbohydrates_100g, fat_100g
    }
}
private struct USDASearchResponse: Decodable { let foods: [USDAFood] }
private struct USDAFood: Decodable {
    let description: String
    let foodNutrients: [USDANutrient]
}
private struct USDANutrient: Decodable {
    let nutrientId: Int
    let value: Double?
}
