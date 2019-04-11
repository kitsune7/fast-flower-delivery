ruleset twilio_sms {
  meta {
    configure using account_sid = "Ask Dustin if you want to use"
                    auth_token = "Ask Dustin if you want to use"
    provides
        send_sms,
        messages
  }

  global {
    send_sms = defaction(to, from, message) {
       base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>
       http:post(base_url + "Messages.json", form = {
                "From":from,
                "To":to,
                "Body":message
            })
    }

    messages = function(to, from, pageSize) {
            base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>;
            q = {};
            q = q.put({"PageSize":pageSize.defaultsTo(null)});
            q = q.put({"To":to.defaultsTo(null)});
            q = q.put({"From":from.defaultsTo(null)});
            q.klog("Query string before get request: ");
            res = http:get(base_url + "Messages.json", qs = q).klog("Raw Res: ");
            res{"content"}.decode(){"messages"}.klog("Decoded res");
        }
  }
}

