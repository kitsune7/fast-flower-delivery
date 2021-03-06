ruleset driver {
  meta {
    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.wrangler alias wrangler
    
    shares __testing // Testing
    , getCurrentOrder, getDriverName, getLocation, getPhoneNumber // Entity
    , getMyEci // Functions
  }
  global {
    /*******************
     *    Questions    *
     ******************/    

    /*******************
     *     Testing     *
     ******************/
    __testing = { "queries":
      [ { "name": "__testing" }
      , { "name": "getCurrentOrder" }
      , { "name": "getDriverName" }
      , { "name": "getLocation" }
      , { "name": "getPhoneNumber" }
      , { "name": "getMyEci" }
      ] , "events":
      [ { "domain": "driver", "type": "offer" }
      , { "domain": "driver", "type": "delivered" }
      , { "domain": "driver", "type": "update_order", "attrs": [ "orderId", "pickupTime", "deliveryAddress", "customerPhone", "customerName", "assignedDriver", "hasBeenDelivered" ] }
      , { "domain": "driver", "type": "update_name", "attrs": [ "name" ] }
      , { "domain": "driver", "type": "update_location", "attrs": [ "location" ] }
      , { "domain": "driver", "type": "update_phone", "attrs": [ "phoneNumber" ] }
      , { "domain": "driver", "type": "reset" }
      ]
    }
    
    /********************
     * Entity Variables *
     *******************/
     getCurrentOrder = function() { ent:currentOrder.defaultsTo({}) }
     getDriverName = function() { ent:driverName.defaultsTo("Bob Driver") }
     getLocation = function() { ent:location.defaultsTo("Spanish Fork, UT") }
     getPhoneNumber = function() { ent:phoneNumber.defaultsTo("7027670013") }
     
     /*******************
      *   Functions     *
      ******************/
      getMyEci = function() {      
        wrangler:channel("main", null, null){"id"}.klog("MY ECI: ")
      }
  }
  
  /***************************
   *       Main Rules        *
   **************************/
  /* Check to see if you already have a current order, if not, check requirements (or something) and send event to store pico in response ¯\_(ツ)_/¯ */
  rule respond_to_offer {
    select when driver find_driver
    pre {
      I = "".klog("ENTERING RESPOND_TO_OFFER ---")
      orderId = event:attr("order_id").klog("ORDER_ID: ")
      eci = event:attr("store_eci").klog("STORE ECI: ")
      s = getCurrentOrder().length().klog("LENGTH: ")
    }
    if (getCurrentOrder().length() == 0) then
      event:send( { "eci": eci, "domain": "order", "type": "apply", 
                    "attrs": { "store_eci": eci, "eci": getMyEci(), "order_id": orderId, "driver_name": getDriverName(), "phone_number": getPhoneNumber(), "driver_location": getLocation() } } )
    fired {

    }
  }
  
  rule accept_assignment {
    select when driver assign
    pre {
      storeEci = event:attr("store_eci")
      orderId = event:attr("order_id")
      pickupTime = event:attr("pickup_time")
      deliveryAddress = event:attr("delivery_address")
      customerPhone = event:attr("customer_phone")
      customerName = event:attr("customer_name")
      order = { "store_eci": storeEci,
                "order_id": orderId,
                "pickup_time": pickupTime,
                "delivery_address": deliveryAddress,
                "customer_phone": customerPhone,
                "customer_name": customerName,
                "assigned_driver": meta:eci,
                "has_been_delivered": "false"
      }
    }
    always {
      ent:currentOrder := order
    }
  }
  
  rule confirm_delivery {
    select when driver delivered
    event:send( { "eci": getCurrentOrder(){"store_eci"}, "domain": "order", "type": "complete",
                  "attrs": { "order_id": getCurrentOrder(){"order_id"}, "deliveryTime": time:now(), "driverRating": event:attr("rating") } } )
    always {
      clear ent:currentOrder;
    }
  }
  
  /***************************
   *      Helper Rules       *
   **************************/
  rule update_current_order {
    select when driver update_order
    pre {
      orderId = event:attr("orderId")
      pickupTime = event:attr("pickupTime")
      deliveryAddress = event:attr("deliveryAddress")
      customerPhone = event:attr("customerPhone")
      customerName = event:attr("customerName")
      assignedDriver = event:attr("assignedDriver")
      hasBeenDelivered = event:attr("hasBeenDelivered")
      order = { "order_id": orderId,
                "pickup_time": pickupTime,
  			        "delivery_address": deliveryAddress,
  			        "customer_phone": customerPhone,
  			        "customer_name": customerName,
			          "assigned_driver": assignedDriver,
  		  	      "has_been_delivered": hasBeenDelivered
              }
    }
    always {
      ent:currentOrder := order
    }
  }
  
  rule update_name {
    select when driver update_name
    always {
      ent:driverName := event:attr("name")
    }
  }
  
  rule update_location {
    select when driver update_location
    always {
      ent:location := event:attr("location")
    }
  }
  
  rule update_number {
    select when driver update_phone
    always {
      ent:phoneNumber := event:attr("phoneNumber")
    }
  }
   
  rule clear_driver {
    select when driver reset
    always {
      clear ent:currentOrder;
      clear ent:driverName;
      clear ent:location;
      clear ent:phoneNumber;
    }
  }
  
  rule auto_accept {
    select when wrangler inbound_pending_subscription_added
    fired {
      raise wrangler event "pending_subscription_approval"
        attributes event:attrs
    }
  }
}
