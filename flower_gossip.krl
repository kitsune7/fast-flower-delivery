ruleset flower_gossip {
  meta {
    use module io.picolabs.subscription alias Subscriptions
    
    shares __testing, //Testing
           randomInt, testPeer, log, getEcis, createLogEntry, test, //Helpers
           getState, getOffers, getSeq, getN, getProcessStatus, //Entity
           getPeer, getDifferences, getRandomPeer, prepareMessage, getRumors, getSeen //Functions
  }
  global {
    /*********************
     *      TESTING      *
     *********************/
    __testing = { "queries":
      [ { "name": "__testing" }
      //, { "name": "randomInt", "args": [ "upper" ] }
      //, { "name": "testPeer" }
      //, { "name": "log", "args": [ "v", "m" ] }
      , { "name": "getEcis" }
      //, { "name": "createLogEntry", "args": [ "temp", "timestamp" ] }
      , { "name": "test" }
      , { "name": "getState" }
      , { "name": "getOffers" }
      , { "name": "getSeq" }
      , { "name": "getN" }
      , { "name": "getProcessStatus" }
      , { "name": "getPeer", "args": [ "state", "val" ] }
      , { "name": "getDifferences", "args": [ "eci" ] }
      , { "name": "prepareMessage", "args": [ "type" ] }
      , { "name": "getRumors" }
      , { "name": "getSeen" }
      ] , "events":
      [ { "domain": "gossip", "type": "heartbeat" }
      , { "domain": "gossip", "type": "rumor" }
      , { "domain": "gossip", "type": "seen" }
      , { "domain": "driver", "type": "offer", "attrs": [ "temperature", "timestamp" ] }
      , { "domain": "gossip", "type": "process", "attrs": [ "status" ] }
      , { "domain": "gossip", "type": "new_n_value", "attrs": [ "n" ] }
      , { "domain": "gossip", "type": "clear" }
      , { "domain": "gossip", "type": "update", "attrs": [ "from", "picoId", "val" ] }
      ]
    }
    
    /*********************
     * HELPER FUNCTIONS  *
     *********************/
    randomInt = function(upper) { random:integer(upper) }
    testPeer = function() { getPeer(getState(), 0) }
    log = function(v, m) { v.klog(m + ": ") }
    getEcis = function() { Subscriptions:established("Tx_role", "sensor").map(function(v) { v{"Tx"} }) }
    createLogEntry = function(orderId, timestamp, eci) {
      log("", "ENTERING CREATE LOG ENTRY");
      {
       "MessageID": meta:picoId + ":" + getSeq(),
       "SensorID": meta:picoId,
       "OrderID": orderId,
       "Timestamp": timestamp,
       "Store_Eci": eci
      }.klog("NEW LOG ENTRY: ")
    }
    test = function() {
     results = {};
     highestMsg = getOffers().values().map(function(v) {v.keys().reverse().head()});
     str = highestMsg[0].split(re#:#);
     results = {}.put(str[0], str[1].as("Number"));
     highestMsg.reduce(function(a,b) { str = b.split(re#:#); a.put(str[0], str[1].as("Number")) }, results)
    }
    
    /*********************
     * ENTITY VARIABLES  *
     *********************/
    getState = function() { ent:state.defaultsTo({}) }
    getOffers = function() { ent:offers.defaultsTo({}) }
    getSeq = function() { ent:seq.defaultsTo(0) }
    getN = function() { ent:n.defaultsTo("10") }
    getProcessStatus = function() { ent:process.defaultsTo("on") }
    
    /*********************
     *     FUNCTIONS     *
     *********************/
    getPeer = function(state, val) {
      log("", "ENTERING GET PEER");
      differences = ((getState() == {}) => getEcis().map(function(v) {{}.put(v, getRumors(v).length()-1)}) | getEcis().map(function(v) {{}.put(v, getDifferences(v))})).klog("DIFFERENCES: ");
      x = differences.collect(function(v){(v.values()[0] < 0) => "neg" | "nonneg"});
      type = (x{"nonneg"}.length() == 0) => "seen" | "rumor";
      results = (type == "seen") => [].append(differences[randomInt(differences.length() - 1)].keys()[0]) | [].append(differences.reduce(function(a,b) { (a.values()[0] > b.values()[0]) => a | b }).keys()[0]);
      results.append(type)
    }
    
    getDifferences = function(eci) {
      results = (getState(){eci}.isnull()) => [getRumors(eci).length()-1] | getState(){eci}.map(function(v,k) { (getSeen(){k}.isnull()) => -1 | getSeen(){k} - v }).values();
      results.sort("numeric");
      results.reverse();
      results[0]
    }

    prepareMessage = function(eci, type) {
      log("", "ENTERING PREPARE MESSAGE");
      ((type == "seen") => getSeen() | getRumors(eci)).klog("RESULTS OF PREPARE MESSAGE: ")
    }
    
    getRumors = function(eci) {
      results = getOffers().values().map(function(v) { v.values() });
      rumorsR([], results, 0).filter(function(x) { getState(){eci}{x{"MessageID"}}.isnull() });
    }
    
    rumorsR = function(array, array2, index) {
      array = array.append(array2[index]);
      (array2[index+1].isnull()) => array | rumorsR(array, array2, index + 1)
    }
    
    getSeen = function() {
      log("", "ENTERING PREPARE SEEN");
      results = {};
      highestMsg = getOffers().values().map(function(v) {v.keys().reverse().head()});
      str = highestMsg[0].split(re#:#);
      results = {}.put(str[0], str[1].as("Number"));
      highestMsg.reduce(function(a,b) { str = b.split(re#:#); a.put(str[0], str[1].as("Number")) }, results)
    }
  }
  
  /********************************************
   *                 RULES                    *
   ********************************************/
   
             /*******************
              *    MAIN RULES   *
              *******************/
  rule process_gossip_heartbeat {
    select when gossip heartbeat where getProcessStatus() == "on"
    pre {
      I = log("", "ENTERING PROCESS_GOSSIP_HEARTBEAT")
      getPeerResults = getPeer(getState(), 0).klog("RESULT OF GETPEER: ")
      subscriber = getPeerResults[0]
      type = getPeerResults[1]
      m = prepareMessage(subscriber, type)
      results = m.map(function(v) { v{"MessageID"} }).map(function(y) { y.split(re#:#) }).reverse()
    }
    event:send( {"eci": subscriber, "domain": "gossip", "type": "message",
                 "attrs": { "picoId": meta:picoId, "type": type, "message": m } } )
    always {
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": getN()});
      raise gossip event "update" attributes { "from": subscriber, "picoId": results[0][0], "val": results[0][1] } if (type == "rumor");
      X = "".klog("EXITING PROCESS_GOSSIP_HEARTBEAT")
    }
  }
  
  rule handle_message {
    select when gossip message where (not message.isnull())
    pre {
      I = log("", "ENTERING HANDLE_MESSAGE")
      type = event:attr("type").klog("TYPE: ")
      message = event:attr("message").klog("MESSAGE: ")
      picoId = event:attr("picoId").klog("PICO ID: ")
    }
    always {
      raise gossip event "rumor" attributes { "rumors": message } if (type == "rumor");
      raise gossip event "seen" attributes { "picoId": picoId,  "seen": message } if (type == "seen")
    }
  }
  
  rule respond_to_rumor {
    select when gossip rumor where (not event:attr("rumors").isnull())
    foreach event:attr("rumors").filter(function(v) { not v.isnull() }) setting(rumor) 
    pre {
      I = log("", "ENTERING RESPOND_TO_RUMOR")
      x = rumor.klog("RUMOR: ")
      messageId = rumor{"MessageID"}.split(re#:#).klog("MESSAGE ID: ")
      picoId = messageId[0].klog("PICO ID: ")
      seqNum = messageId[1].as("Number").klog("SEQ NUM: ")
      oldSeq = getState(){meta:eci}{picoId}
    }
    always {
      raise gossip event "update" attributes { "from": meta:eci, "picoId": picoId, "val": seqNum} if (seqNum == oldSeq + 1);
      raise driver event "find_driver" attributes { "from_rumor": "true", "order_id": rumor{"OrderID"}, "store_eci": rumor{"Store_Eci"} };
      ent:offers := getOffers().put([picoId, picoId + ":" + seqNum], rumor)
    }
  }
  
  rule respond_to_seen {
    select when gossip seen where (not event:attr("seen").isnull())
    pre {
      I = log("", "ENTERING RESPOND_TO_SEEN")
      incomingPicoId = event:attr("picoId")
      seen = event:attr("seen").klog(incomingPicoId + ": ")
      neededRumors = seen.filter(function(v,k) { getSeen(){k} > v })
      rumors = neededRumors.map(
                                  function(v1,k1) {
                                    getOffers{k1}.filter(
                                                          function(v2,k2) {
                                                            str = k2.split(re#:#);
                                                            str[1] > v1
                                                          })
                                  }
                                )
    }
    if (rumors.length() > 0) then
      event:send( { "eci": meta:eci, "domain": "gossip", "type": "rumor", "attrs": { "rumors": rumors } } )
    always {
      ent:state := getState().put(meta:eci, seen).klog("EXITING RESPOND_TO_SEEN");
    }
  }
  
  rule add_new_offer {
    select when driver find_driver where (event:attr("from_rumor").isnull())
    pre {
     I = log("", "ENTERING ADD_NEW_OFFER")
     orderId = event:attr("order_id")
     timestamp = time:now()
     eci = event:attr("store_eci")
    }
    always {
      ent:offers := getOffers().put([meta:picoId, meta:picoId + ":" + getSeq()], createLogEntry(orderId, timestamp, eci));
      ent:seq := getSeq() + 1
    }
  }
  
            /*******************
             *     HELPERS     *
             *******************/
  // Updates the value of n; Used to determine length of wait for heartbeats
  rule update_n_value {
    select when gossip new_n_value
    pre {
      n = event:attr("n").klog("NEW N: ")
    }
    always {
      ent:n := n
    }
  }
  
  // Updates the value of process; Used to start and stop heartbeat
  rule update_process_status {
    select when gossip process
    pre {
      status = event:attr("status").klog("NEW STATUS: ")
    }
    always {
      ent:process := status
    }
  }
  
  // Used to reset ruleset
  rule clear_gossip {
    select when gossip clear
    always {
      clear ent:state;
      clear ent:offers;
      clear ent:seq;
      clear ent:n;
      clear ent:process
    }
  }
  
  // Used for testing; Add a new state value
  rule update_state {
    select when gossip update where (not event:attr("picoId").isnull())
    pre {
      from = event:attr("from")
      state = {}.put(event:attr("picoId"), event:attr("val").as("Number"))
    }
    always {
      
      ent:state := getState().put([from, event:attr("picoId")], event:attr("val"))
    }
  }
}
