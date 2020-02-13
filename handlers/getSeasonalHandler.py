from urllib.parse import urlencode
from helpers import kotrikhelper
import asyncio

import requests
from tornado.ioloop import IOLoop
import tornado.gen
import tornado.web
import json
import time

from common.log import logUtils as log
from common.web import requestsManager


class handler(requestsManager.asyncRequestHandler):
	@tornado.web.asynchronous
	@tornado.gen.engine
	def asyncGet(self):
		try:
			# Get user IP
			requestIP = self.getRequestIP()
			self.flush()

			time.sleep(2)
			
			ppybg = requests.get("https://osu.ppy.sh/web/osu-getseasonal.php")
			user = kotrikhelper.getUserIdByIP(requestIP)
			if user == 0:
				self.write(ppybg.text)
				return
			
			bgs = kotrikhelper.getUserBGs(user)
			if bgs[0] == "":
				self.write(ppybg.text)
				return

			self.write(json.dumps(bgs))
			self.finish()
		except Exception as e:
			log.error("check-seasonal failed: {}".format(e))
			self.write("")
