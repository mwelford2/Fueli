# USDA meal lookup fixtures

Captured 2026-11-01 from the public USDA FoodData Central v1 API using its documented DEMO_KEY. No personal keys or meal data are included.

- `POST /foods/search`: query `everything bagel` or `cream cheese`, pageSize 50, dataType `["Foundation", "SR Legacy", "Survey (FNDDS)"]`.
- `GET /food/2707684`: Bagel, Survey (FNDDS).
- `GET /food/2346385`: Cream cheese, full fat, block, Foundation.
- `GET /food/173418`: Cheese, cream, SR Legacy. Unlike the Foundation record, this record includes an explicit fiber value of zero.

The search fixtures retain all 50 food identities and one complete set of consumed search-nutrient fields; unrelated metadata and other search nutrient arrays are omitted to keep the fixtures small. Detail fixtures retain every nutrient's ID, unit and amount. Values are actual responses, not invented test nutrition.

FoodData Central data: USDA Agricultural Research Service, CC0/public domain. API contract: https://fdc.nal.usda.gov/api-guide/ (OpenAPI v1.0.1). Context7 returned a third-party Python client reference; request behavior was verified against USDA's own documentation and live responses.

These fixtures demonstrate matching and arithmetic for this example; they do not establish broad food-identification accuracy. A generic bagel omits a verified everything topping and always requires explicit review.
