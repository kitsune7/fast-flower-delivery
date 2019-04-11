ruleset store_pico {
  meta {
    shares __testing, get_orders, get_order_by_id
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    
    // Store address is set to TMCB building BYU
    store_lat = 40.249213
    store_long = 111.651413
    
    get_orders = function() {
      ent:orders
    }
      
    get_order_by_id = function(id) {
      ent:orders{id}
    }
  }

  rule order_received {
    select when order new 
    pre {
	// Object received is in this format
 	// 	{	
  	// 	  pickup_time:	Date/Time				
 	// 	  delivery_time:	Date/Time				
 	// 	  delivery_address:	string				
  	// 	  customer_phone:	string		
  	// 	  customer_name: string
  	// 	}
  		
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
  		"customer_name": customer_name
  	}.klog("NEW ORDER")
    }
      		
	always {
	 	ent:orders{id} := new_order;
	
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

   rule notify_customer {
    select when notify customer
    pre {
      	// When a driver has been assigned, the customer should be notified via text
      	// The text includes the name and phone number of the driver, as well as the customer's order_id
      
      	// Object received is in this format
 	// 	{	
  	//    "driver_phone": number
  	//    "driver_name": string
  	//    "order_id": number
  	//  }
  		
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

