<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\EventResource;
use App\Models\Event;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Pagination\CursorPaginator;
use Illuminate\Pagination\Paginator;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

/**
 * Every pagination shape Laravel ships, plus the ordinary CRUD calls the SDK's
 * Codable path is tested against.
 */
class EventController extends Controller
{
    public function index(Request $request): LengthAwarePaginator
    {
        return $this->query()->paginate($this->perPage($request))->withQueryString();
    }

    /** Length-aware pagination wrapped in an API Resource: data + links + meta. */
    public function resource(Request $request): AnonymousResourceCollection
    {
        return EventResource::collection(
            $this->query()->paginate($this->perPage($request))->withQueryString()
        );
    }

    public function simple(Request $request): Paginator
    {
        return $this->query()->simplePaginate($this->perPage($request))->withQueryString();
    }

    public function cursor(Request $request): CursorPaginator
    {
        return $this->query()->cursorPaginate($this->perPage($request))->withQueryString();
    }

    public function show(Event $event): EventResource
    {
        return new EventResource($event);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'min:3', 'max:255'],
            'description' => ['nullable', 'string'],
            'starts_at' => ['required', 'date'],
        ]);

        $event = Event::query()->create($data);

        return (new EventResource($event))->response()->setStatusCode(201);
    }

    public function destroy(Event $event): Response
    {
        $event->delete();

        return response()->noContent();
    }

    private function query()
    {
        return Event::query()->orderBy('id');
    }

    private function perPage(Request $request): int
    {
        return max(1, min(100, (int) $request->integer('per_page', 10)));
    }
}
