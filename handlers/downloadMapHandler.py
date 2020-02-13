import tornado.gen
import tornado.web
import re

from common.web import requestsManager
from common.sentry import sentry

MODULE_NAME = "direct_download"
class handler(requestsManager.asyncRequestHandler):
	"""
	Handler for /d/
	"""
	@tornado.web.asynchronous
	@tornado.gen.engine
	@sentry.captureTornado
	def asyncGet(self, bid):
		try:
			noVideo = bid.endswith("n")
			if noVideo:
				bid = bid[:-1]
			bid = int(bid)

			self.set_status(302, "Moved Temporarily")
			url = "https://storage.kurikku.pw/d/{}{}".format(bid, "?novideo" if noVideo else "")
			self.add_header("Location", url)
			self.add_header("Cache-Control", "no-cache")
			self.add_header("Pragma", "no-cache")
		except ValueError:
			self.set_status(400)
			self.write("Invalid set id")

#idk but this needs....................
class handlerSets(requestsManager.asyncRequestHandler):
	"""
	Handler for /beatmapsets/
	"""
	@tornado.web.asynchronous
	@tornado.gen.engine
	@sentry.captureTornado
	def asyncGet(self, megaepic):
		try:
			noVideo = megaepic.endswith("n")
			# sid#mode/bid
			# sid
			arguments = re.split(r"#(.*)\/", megaepic)
			if len(arguments) < 1:
				url = "https://kurikku.pw"
			
			if len(arguments) < 3:
				noVideo = arguments[0].endswith("n")
				url = "https://storage.kurikku.pw/d/{}{}".format(arguments[0], "?novideo" if noVideo else "")
			
			if len(arguments) == 3:
				noVideo = megaepic.endswith("n")
				url = "https://storage.kurikku.pw/d/{}{}".format(arguments[2], "?novideo" if noVideo else "")
			
			self.set_status(302, "Moved Temporarily")
			self.add_header("Location", url)
			self.add_header("Cache-Control", "no-cache")
			self.add_header("Pragma", "no-cache")
		except ValueError:
			self.set_status(400)
			self.write("Invalid set id")
