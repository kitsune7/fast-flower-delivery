ruleset store {
  meta {
    shares __testing, get_orders, get_order_by_id, get_incomplete_orders, get_unassigned_orders
  }

  global {
    // Store address is set to TMCB building BYU
    store_lat = 40.249213
    store_long = 111.651413

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

      new_order = {
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

    always {
      ent:orders{order_id} := new_order;

      raise order event "find_driver" attributes {
        "order_id": order_id,
        "pickup_time": pickup_time,
        "delivery_address": delivery_address,
        "customer_phone": customer_phone,
        "customer_name": customer_name,
        "store_lat": store_address,
        "store_long": store_long
      }
    }
  }
  
  rule applied_for_job {
    select when order apply
    pre {
      driver_eci = event:attr("eci")
      order_id = event:attr("order_id")
      name = event:attr("name")
      phone = event:attr("phone")
      location = event:attr("location")
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
      driver_name = event:attr("driver_name")
      order_id = event:attr("order_id")
      order = get_order_by_id(order_id).klog("GETTING ORDER BY ID")
      customer_phone = order{"customer_phone"}.klog("CUSTOMER PHONE")
      customer_name = order{"customer_name"}.klog("CUSTOMER NAME")
      message = "Hello " + customer_name  + ", "  + driver_name + " has been assigned to deliver your order, and can be reached at - " + driver_phone
    }
    
    twilio:send_sms(customer_phone, store_phone, message)
  }
}
