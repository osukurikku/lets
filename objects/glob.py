import personalBestCache
import userStatsCache

import prometheus_client

from common.ddog import datadogClient
from common.files import fileBuffer, fileLocks
from common.web import schiavo

try:
	with open("version") as f:
		VERSION = f.read().strip()
except:
	VERSION = "Unknown"
ACHIEVEMENTS_VERSION = 1

DATADOG_PREFIX = "RegularPho"
db = None
redis = None
conf = None
application = None
pool = None

busyThreads = 0
debug = False
sentry = False

stats = {
	"request_latency_seconds": prometheus_client.Histogram(
		"request_latency_seconds",
		"Time spent processing requests",
		("method", "endpoint")
	),
	"pp_calc_latency_seconds": prometheus_client.Histogram(
		"pp_calc_latency_seconds",
		"Time spent calculating pp",
		("game_mode",),
		buckets=(
			.0005, .001, .0025, .005, .0075, .01, .025, .05, .075,
			.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0, float("inf")
		)
	),

	"pp_calc_failures": prometheus_client.Counter(
		"pp_failures",
		"Number of scores that couldn't have their pp calculated",
		("game_mode",)
	),
	"replay_upload_failures": prometheus_client.Counter(
		"replay_failures",
		"Number of replays that couldn't be uploaded to S3",
	),
	"replay_download_failures": prometheus_client.Counter(
		"replay_download_failures",
		"Number of replays that couldn't be served",
	),
	"osu_api_failures": prometheus_client.Counter(
		"osu_api_failures",
		"Number of osu! api errors",
		("method",)
	),
	"osu_api_requests": prometheus_client.Counter(
		"osu_api_requests",
		"Number of requests towards the osu!api",
		("method",)
	),
	"submitted_scores": prometheus_client.Counter(
		"submitted_scores",
		"Number of submitted scores",
		("game_mode", "completed")
	),
	"served_leaderboards": prometheus_client.Counter(
		"served_leaderboards",
		"Number of served leaderboards",
		("game_mode",)
	),

	"in_progress_requests": prometheus_client.Gauge(
		"in_progress_requests",
		"Number of in-progress requests",
		("method", "endpoint")
	),
}

# Cache and objects
fLocks = fileLocks.fileLocks()
userStatsCache = userStatsCache.userStatsCache()
personalBestCache = personalBestCache.personalBestCache()
fileBuffers = fileBuffer.buffersList()
dog = datadogClient.datadogClient()
schiavo = schiavo.schiavo()
achievementClasses = {}