<?php
use Illuminate\Support\Facades\Route;
Route::get('/', function () {
    return response('<h1>Laravel API</h1><p>Фронт (Vue) отдается из /public.</p>', 200);
});
