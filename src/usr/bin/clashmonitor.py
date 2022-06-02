#!/usr/bin/env python

try:
    # python 2
    from urllib import quote_plus
except ImportError:
    # python 3
    from urllib.parse import quote_plus

import httplib
import json
import os, sys
import subprocess 
import hashlib
import random

class ClashMonitor:

    def __init__(self, controller, secret):
        self.controller = controller
        self.secret = secret
        self.conn = self.rest_connection()
        self.conn.set_debuglevel(0)
        
        self.headers = {
            'Authorization': 'Bearer ' + self.secret
        }

    def __del__(self):
        self.conn.close()

    def rest_connection(self):
        return httplib.HTTPConnection(self.controller)

    def rest_get(self, url):
        self.conn.request('GET', url, headers=self.headers)

        resp = self.conn.getresponse()
        data = resp.read()
        
        return json.loads(data)

    def rest_put(self, url, body):
        self.conn.request('PUT', url, body, self.headers)

        resp = self.conn.getresponse()
        return resp.status

    def get_providers(self):
        providers = self.rest_get('/providers/proxies')
        return providers['providers'].keys()

    def get_proxies(self):
        proxies = self.rest_get('/proxies')
        return proxies['proxies']

    def update_proxy(self, group, proxy):
        self.rest_put('/proxies/' + quote_plus(group), json.dumps({"name": proxy}))

    def reload_config(self):
        self.rest_put('/configs?force=true', '{}')

    def test(self):
        challenge = str(random.randrange(1000000))
        challenge_md5 = hashlib.md5(challenge).hexdigest()
        try:
            output = subprocess.check_output(['curl', '-q', '-s', '--connect-timeout', '5', '--max-time', '10', 'https://rst.im/ip/?challenge=' + challenge])
        except:
            return False

        return output.index(challenge_md5) > -1

    def monitor(self):
        providers = self.get_providers()
        
        proxies = self.get_proxies()

        connected = []
        tested = []
        
        for i in providers: 
            if i in proxies and 'now' in proxies[i]:

                current = to_test = proxies[i]['now']

                ptr = -1

                while True:
                    # check and test
                    if to_test in tested:
                        if to_test in connected:
                            if to_test == current:
                                # current ok
                                pass
                            else:
                                # select current
                                self.update_proxy(i, to_test)
                                current = to_test
                                print(i.encode('utf-8') + " Changed to tested ? " + to_test.encode('utf-8'))
                            break
                        else:
                            # tested but not connected
                            # try to find one in connected, if that one is also in candidates
                            picked = False
                            for j in connected:
                                if j in proxies[i]['all']:
                                    self.update_proxy(i, j)
                                    picked = True
                                    current = j
                                    print(i.encode('utf-8') + " Changed to tested " + j.encode('utf-8'))
                                    break

                            if picked:
                                break

                            # try another candicate to test
                            ptr += 1
                            to_test = proxies[i]['all'][ptr]
                    else:
                        tested.append(to_test)

                        if to_test != current:
                            self.update_proxy(i, to_test)
                            current = to_test
                            print(i.encode('utf-8') + " Try: " + to_test.encode('utf-8'))

                        if self.test():
                            connected.append(to_test)
                            if current != to_test:
                                current = to_test
                                print(i.encode('utf-8') + " Changed to " + to_test.encode('utf-8'))
                            break
                        else:
                            # find next 
                            ptr += 1
                            to_test = proxies[i]['all'][ptr]




if __name__ == '__main__':
    if len(sys.argv) > 1:
        # load config from script
        secret = subprocess.check_output(['/usr/bin/yq', '.secret', '/run/clash/utun/config.yaml']).strip()
        controller = subprocess.check_output(['/usr/bin/yq', '.external-controller', '/run/clash/utun/config.yaml']).strip().replace('0.0.0.0', '127.0.0.1')

        monitor = ClashMonitor(controller=controller, secret=secret)

        if sys.argv[1] == 'reload':
            # reload config
            monitor.reload_config()
        elif sys.argv[1] == 'test':
            if monitor.test():
                print("Connected")
            else:
                print("Connection failed")
        elif sys.argv[1] == 'monitor':
            monitor.monitor()
    else:
        # monitor mode by default
        print("Usage: %s COMMAND" % sys.argv[0])
        print("Commands: ")
        print("\treload")
        print("\ttest")
        print("\tmonitor")
