<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Upload;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;

/**
 * The two upload paths a Laravel API offers: multipart through the app, and a
 * signed URL the client uploads to directly.
 */
class UploadController extends Controller
{
    private const DIRECT_UPLOAD_TTL_MINUTES = 5;

    /** Ordinary multipart/form-data upload. */
    public function avatar(Request $request): JsonResponse
    {
        $data = $request->validate([
            'file' => ['required', 'file', 'max:4096'],
            'caption' => ['nullable', 'string', 'max:255'],
        ]);

        $file = $data['file'];
        $path = $file->store('avatars', 'local');

        return response()->json([
            'path' => $path,
            'original_name' => $file->getClientOriginalName(),
            'mime' => $file->getClientMimeType(),
            'size' => Storage::disk('local')->size($path),
            'caption' => $data['caption'] ?? null,
            'fields' => (object) $request->except(['file']),
        ], 201);
    }

    /** Issues a short-lived signed URL the client uploads the bytes to. */
    public function authorizeUpload(Request $request): JsonResponse
    {
        $data = $request->validate([
            'filename' => ['required', 'string', 'max:255'],
            'content_type' => ['required', 'string', 'max:255'],
            'size' => ['nullable', 'integer', 'min:1', 'max:10485760'],
        ]);

        $uuid = (string) Str::uuid();
        $key = 'direct/'.$uuid.'/'.$data['filename'];

        $url = URL::temporarySignedRoute(
            'uploads.storage',
            now()->addMinutes(self::DIRECT_UPLOAD_TTL_MINUTES),
            ['uuid' => $uuid]
        );

        return response()->json([
            'url' => $url,
            'method' => 'PUT',
            'headers' => ['Content-Type' => $data['content_type']],
            'key' => $key,
            'bucket' => 'local',
            'uuid' => $uuid,
        ]);
    }

    /**
     * Stands in for object storage.
     *
     * It is reached through a signed URL and never sees the app's bearer token,
     * exactly like a real presigned upload.
     */
    public function storage(Request $request, string $uuid): JsonResponse
    {
        $body = $request->getContent();

        if ($body === '') {
            return response()->json(['message' => 'Empty upload.'], 422);
        }

        Storage::disk('local')->put($this->objectPath($uuid), $body);

        return response()->json([
            'uuid' => $uuid,
            'size' => strlen($body),
            'content_type' => $request->header('Content-Type'),
            'authorization' => $request->header('Authorization'),
        ]);
    }

    /** Records an upload the client sent straight to storage. */
    public function complete(Request $request): JsonResponse
    {
        $data = $request->validate([
            'uuid' => ['required', 'uuid'],
            'key' => ['required', 'string'],
            'filename' => ['nullable', 'string', 'max:255'],
        ]);

        $path = $this->objectPath($data['uuid']);

        if (! Storage::disk('local')->exists($path)) {
            return response()->json([
                'message' => 'The upload was never stored.',
            ], 422);
        }

        $upload = Upload::query()->create([
            'user_id' => $request->user()?->id,
            'uuid' => $data['uuid'],
            'key' => $data['key'],
            'filename' => $data['filename'] ?? basename($data['key']),
            'size' => Storage::disk('local')->size($path),
        ]);

        return response()->json([
            'id' => $upload->id,
            'uuid' => $upload->uuid,
            'key' => $upload->key,
            'filename' => $upload->filename,
            'size' => $upload->size,
            'created_at' => $upload->created_at,
        ], 201);
    }

    private function objectPath(string $uuid): string
    {
        return 'direct-uploads/'.$uuid;
    }
}
