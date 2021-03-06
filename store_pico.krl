ruleset store_pico {
  meta {
    use module twilio_sms alias twilio
    use module distance
    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.wrangler alias wrangler
    shares __testing, get_orders, get_order_by_id, get_incomplete_orders, get_unassigned_orders, get_driver_eci
  }

  global {
     /*******************
     *     Testing     *
     ******************/
    __testing = { "queries":
      [ { "name": "__testing" }
      , { "name": "get_orders" }
      , { "name": "get_driver_eci" }
      //, { "name": "getLocation" }
      //, { "name": "getPhoneNumber" }
      ] , "events":
      [ { "domain": "order", "type": "new", "attrs": [ "pickup_time", "delivery_address", "customer_phone", "customer_name" ] }
      , { "domain": "orders", "type": "clear" }
      , { "domain": "driver", "type": "selected", "attrs": [ "order_id" ] }
      //, { "domain": "driver", "type": "update_location", "attrs": [ "location" ] }
      //, { "domain": "driver", "type": "update_phone", "attrs": [ "phoneNumber" ] }
      //, { "domain": "driver", "type": "reset" }
      ]
    }

    // Store address is set to TMCB building BYU
    store_address = "BYU, TMCB, Provo, UT"
    delay_seconds = 15 // The number of seconds to wait for collecting all the driver responses
    store_phone = "+13852478058"

    get_driver_eci = function () {
      subscriptions = Subscriptions:established().klog("subscriptions");
      rand_int = random:integer(subscriptions.length() - 1);
      {
        "Tx": subscriptions[rand_int]{"Tx"}.klog("returned val"),
        "Rx": subscriptions[rand_int]{"Rx"}.klog("returned val")
      }
    }

    get_orders = function() {
      ent:orders.defaultsTo([])
    }

    get_order_by_id = function(id) {
        ent:orders{id}
    }

    get_incomplete_orders = function() {
      ent:orders.filter(function(order) {
        order{"has_been_delivered"} == "none" && order{"assigned_driver"} != "none";
      });
    }

    get_unassigned_orders = function() {
      ent:orders.filter(function(order) {
        order{"assigned_driver"} == "none";
      });
    }

    driver_destinations = function (drivers) {
      driver_locations = drivers.map(function (driver) { driver{"location"} });
      driver_locations.join("|")
    }
  }

  rule view_orders {
    select when orders view
    send_directive("View orders", {"orders": get_orders()})
  }

  rule clear_orders {
    select when orders clear
    always {
      clear ent:orders
    }
  }

  rule subscribe_driver {
    select when subscribe driver
    pre {
      name = event:attr("name").klog("subscribing driver")
    }

    fired {
      raise wrangler event "child_creation"
      attributes {"name": name,
                  "color": "#0d915c",
                  "rids": ["driver"]
      }
    }
  }

   rule new_driver_detected {
    select when wrangler new_child_created
    pre {
      name = event:attr("name").klog("NEW CHILD CREATED")
    }

    always {
      name.klog("*** NEW DRIVER ADDED ***");
      raise wrangler event "subscription" attributes {
        "name": name,
        "channel_type": "subscription",
        "Tx_role": "driver",
        "wellKnown_Tx": eci,
        "Rx_role": "driver"
      }
    }
  }

  rule auto_accept {
    select when wrangler inbound_pending_subscription_added
    pre {
      attrs = event:attr.klog("auto accepting")
    }

    fired {
      raise wrangler event "pending_subscription_approval"
        attributes attrs
    }
  }

  rule subscriptionAdded {
    select when wrangler subscription_added
    pre {
      Tx = event:attr("_Tx").klog("SUBSCRIPTION ADDED Tx")
    }
  }

  rule order_received {
    select when order new
    pre {
      /*
        Object received is in this format:
        {
          pickup_time: Date/Time
          delivery_time: Date/Time
          delivery_address: string
          customer_phone: string
          customer_name: string
        }
      */

      // Generate unique id for order
      order_id = random:uuid()

      pickup_time = event:attr("pickup_time").defaultsTo("null")
      delivery_address = event:attr("delivery_address")
      customer_phone = event:attr("customer_phone")
      customer_name = event:attr("customer_name")

      ecis = get_driver_eci()
      tx = ecis{"Tx"}
      rx = ecis{"Rx"}

      new_order = {
        "store_eci": rx,
        "order_id": order_id,
        "pickup_time": pickup_time,
        "delivery_address": delivery_address,
        "customer_phone": customer_phone,
        "customer_name": customer_name,
        "assigned_driver": "none",
        "applied_drivers": [],
        "has_been_delivered": "none"
      }.klog("NEW ORDER")
    }

    if not tx.isnull() then
      event:send({
        "eci": tx,
        "domain": "driver",
        "type": "find_driver",
        "attrs": {
          "store_eci": rx,
          "order_id": order_id,
          "pickup_time": pickup_time,
          "delivery_address": delivery_address,
          "customer_phone": customer_phone,
          "customer_name": customer_name,
          "store_address": store_address,
          "from_rumor": null
        }
      })

    always {
      ent:orders{order_id} := new_order;
      schedule driver event "hire" at time:add(time:now(), {"seconds" : delay_seconds}) attributes {
        "order_id": order_id
      }
    }
  }

  rule applied_for_job {
    select when order apply
    pre {
      store_eci = event:attr("store_eci")
      driver_eci = event:attr("eci")
      order_id = event:attr("order_id")
      name = event:attr("driver_name")
      phone = event:attr("phone_number")
      location = event:attr("driver_location")
      order = ent:orders{order_id}
    }
    always {
      ent:orders{order_id} := order.put(
        ["applied_drivers"],
        order{"applied_drivers"}.union(order{"applied_drivers"}.append({
          "eci": driver_eci,
          "name": name,
          "phone": phone,
          "location": location
        }))
      )
    }
  }

  rule select_closest_driver {
    select when driver hire
    pre {
      order_id = event:attr("order_id").klog("select closest driver!")
      order = ent:orders{order_id}
      drivers = order{"applied_drivers"}.defaultsTo([null])
      results = distance:get_distance(store_address, driver_destinations(drivers))
      driver_index = distance:closest_index(results).klog("driver index")
    }
    always {
      ent:orders{order_id} := order.put(
        ["assigned_driver"],
        drivers.splice(driver_index, 0).head()
      );
      raise driver event "selected" attributes {
        "order_id": order_id
      }
    }
  }

  rule notify_selected_driver {
    select when driver selected
    pre {
      order_id = event:attr("order_id")
      order = ent:orders{order_id}
      driver = order{"assigned_driver"}
    }
    event:send({
      "eci": driver{"eci"},
      "domain": "driver",
      "type": "assign",
      "attrs": {
        "store_eci": order{"store_eci"},
        "order_id": order_id,
        "pickup_time": order{"pickup_time"},
        "delivery_address": order{"delivery_address"},
        "customer_phone": order{"customer_phone"},
        "customer_name": order{"customer_name"}
      }
    })
    fired {
      raise notify event "customer" attributes { "order_id": order_id, "driver_phone": order{"customer_phone"}, "driver_name": order{"driver_name"} }
    }
  }

  rule notify_customer {
    select when notify customer
    pre {
      // When a driver has been assigned, the customer should be notified via text
      // The text includes the name and phone number of the driver, as well as the customer's order_id

      // Object received is in this format:
      // {
      //   "driver_phone": number
      //   "driver_name": string
      //   "order_id": number
      // }

      driver_phone = event:attr("driver_phone")
      order_id = event:attr("order_id")
      order = get_order_by_id(order_id).klog("GETTING ORDER BY ID")
      customer_phone = order{"customer_phone"}.klog("CUSTOMER PHONE")
      customer_name = order{"customer_name"}.klog("CUSTOMER NAME")
      driver_name = order{"assigned_driver"}{"name"}.klog("DRIVER NAME")
      message = "Hello " + customer_name  + ", "  + driver_name + " has been assigned to deliver your order, and can be reached at - " + driver_phone
    }

    twilio:send_sms(customer_phone, store_phone, message)
  }

  rule complete_order {
    select when order complete
    pre {
      order_id = event:attr("order_id")
      order = ent:orders{order_id}
    }
    always {
      ent:orders{order_id} := order.put(["has_been_delivered"], "true")
    }
  }
}
