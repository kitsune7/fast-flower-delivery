ruleset distance {
  meta {
    configure using api_key = "Ask Chris for it"
    provides get_distance, closest_index
  }

  global {
    get_distance = function (origins, destinations) {
      destinations.klog("DESTINATIONS");
      base_url = "https://maps.googleapis.com/maps/api/distancematrix/json";
      q = {};
      q = q.put({ "units": "imperial" });
      q = q.put({ "origins": origins });
      q = q.put({ "destinations": destinations });
      q = q.put({ "key": api_key });
      res = http:get(base_url, qs = q).klog("Raw result: ");
      res{"content"}.decode(){"rows"}.klog("Decoded result: ")
    }
    
    closest_index = function (rows) {
      row_values = rows.map(function (row) {
        row{"elements"}.head(){"distance"}{"value"}
      });
      largest = row_values.reduce(function (a, b) {
        a < b => a | b
      });
      row_values.index(largest)
    }
  }
}
