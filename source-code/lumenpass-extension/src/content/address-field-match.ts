/** Descriptors include names, labels, placeholders, and autocomplete values. */
export const ADDRESS_FIELD_MATCHERS = {
  country: /country\b|country.?name|country.?or.?region|region.?country|country.?region/,
  city: /city\b|town\b|municipality|suburb|locality/,
  state: /state\b|province|region|county|district|prefecture|territory/,
};
