# Open Food Facts fixtures

Captured 2026-11-01 from public, keyless production API reads. No private meals or credentials are included.

- `search.json`: `POST https://search.openfoodfacts.org/search`, `q=cream cheese`, page 1, page_size 5, English, boost_phrase enabled. Keeps actual hits, count and timed_out; omits debug/aggregations. Brands are arrays in this API, unlike the Product Opener product detail's string.
- `cream-cheese-product.json`: `GET https://world.openfoodfacts.org/api/v3/product/9311000999555` with a restricted field list; Australian Cream Cheese, Bega. Preserves the actual response. Nutriments are a 100 g reference; the separate serving is 25 g. Tests verify these bases are not mixed.

Database: Open Food Facts, ODbL; individual contents: Database Contents License. https://world.openfoodfacts.org/data . Data is community-supplied and not guaranteed complete/accurate. A real response fixture demonstrates decoding and arithmetic, not broad matching accuracy. All other product values in tests are explicitly synthetic fixtures.
