import { describe, expect, it } from 'bun:test'
import { statSync } from 'fs'
import { app } from '../src/bun/aponiajs'

const request = (path: string, init?: RequestInit) =>
	app.handle(new Request(`http://127.0.0.1:3000${path}`, init))

describe('AponiaJS benchmark target', () => {
	it('serves the ping route', async () => {
		const response = await request('/')

		expect(response.status).toBe(200)
		expect(response.headers.get('content-type')).toContain('text/plain')
		expect(await response.text()).toBe('Hi')
	})

	it('reads dynamic path and query parameters', async () => {
		const response = await request('/id/42?name=alice&id=ignored')

		expect(response.headers.get('x-powered-by')).toBe('benchmark')
		expect(response.headers.get('content-type')).toContain('text/plain')
		expect(await response.text()).toBe('42 alice')

		const missingName = await request('/id/1?id=1')
		expect(await missingName.text()).toBe('1 ')
	})

	it('parses and serializes JSON', async () => {
		const response = await request('/json', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ hello: 'world' })
		})

		expect(response.headers.get('content-type')).toContain('application/json')
		expect(await response.text()).toBe(JSON.stringify({ hello: 'world' }))
	})

	it('streams the video with its media type', async () => {
		const response = await request('/video')

		expect(response.status).toBe(200)
		expect(response.headers.get('content-type')).toContain('video/mp4')
		expect((await response.arrayBuffer()).byteLength).toBe(
			statSync('public/kyuukurarin.mp4').size
		)
	})

	it('serves static and dynamic background routes', async () => {
		const get = await request('/users/verify/profile')
		expect(await get.text()).toBe('ok')

		const post = await request(
			'/v2/en/users/verify/messages/verify/attachments/verify/submit',
			{ method: 'POST' }
		)
		expect(await post.text()).toBe('ok')
	})
})
