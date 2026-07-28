import {
	Body,
	Controller,
	Get,
	Module,
	Param,
	Post,
	Query,
	Res,
	type RouteResponseSettings
} from '@aponiajs/common'
import { AponiaFactory } from '@aponiajs/platform-elysia'
import { extraRoutes } from '../../extra-routes.mjs'

@Controller()
class BenchmarkController {
	@Get()
	index(@Res() response: RouteResponseSettings) {
		response.headers['content-type'] = 'text/plain'
		return 'Hi'
	}

	@Get('video')
	video(@Res() response: RouteResponseSettings) {
		response.headers['content-type'] = 'video/mp4'
		return Bun.file('public/kyuukurarin.mp4')
	}

	@Get('id/:id')
	query(
		@Param('id') id: string,
		@Query('name') name: string | undefined,
		@Res() response: RouteResponseSettings
	) {
		response.headers['content-type'] = 'text/plain'
		response.headers['x-powered-by'] = 'benchmark'
		return `${id} ${name ?? ''}`
	}

	@Post('json')
	json(@Body() body: unknown) {
		return body
	}
}

class BackgroundController {
	get() {
		return 'ok'
	}

	post() {
		return 'ok'
	}
}

const backgroundPrototype = BackgroundController.prototype
const getDescriptor = Object.getOwnPropertyDescriptor(
	backgroundPrototype,
	'get'
)!
const postDescriptor = Object.getOwnPropertyDescriptor(
	backgroundPrototype,
	'post'
)!

for (const route of extraRoutes) {
	Get(route)(backgroundPrototype, 'get', getDescriptor)
	Post(`${route}/submit`)(backgroundPrototype, 'post', postDescriptor)
}
Controller()(BackgroundController)

@Module({
	controllers: [BenchmarkController, BackgroundController]
})
class AppModule {}

export const app = await AponiaFactory.create(AppModule, { logger: false })

if (import.meta.main) await app.listen(3000)
