/* eslint-disable no-console */

import { NextRequest, NextResponse } from 'next/server';
import { getAuthInfoFromCookie } from '@/lib/auth';

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // ==============================
  // 只保护 admin 页面 和 admin API
  // ==============================

  const isAdminPage = pathname.startsWith('/admin');
  const isAdminApi = pathname.startsWith('/api/admin');

  if (!isAdminPage && !isAdminApi) {
    return NextResponse.next();
  }

  // ==============================
  // 检查是否配置密码
  // ==============================

  if (!process.env.PASSWORD) {
    console.warn('MoonTVPlus PASSWORD not set');

    if (isAdminApi) {
      return new NextResponse('Server misconfigured', { status: 500 });
    }

    const warningUrl = new URL('/warning', request.url);
    return NextResponse.redirect(warningUrl);
  }

  // ==============================
  // 获取 cookie 登录信息
  // ==============================

  const authInfo = getAuthInfoFromCookie(request);

  if (!authInfo) {
    return handleAuthFailure(request);
  }

  // ==============================
  // localstorage 模式
  // ==============================

  if (authInfo.password) {
    if (authInfo.password !== process.env.PASSWORD) {
      return handleAuthFailure(request);
    }

    return NextResponse.next();
  }

  // ==============================
  // token 模式
  // ==============================

  if (!authInfo.username || !authInfo.signature || !authInfo.timestamp) {
    return handleAuthFailure(request);
  }

  return NextResponse.next();
}

// ==============================
// 未授权处理
// ==============================

function handleAuthFailure(request: NextRequest): NextResponse {
  const { pathname } = request.nextUrl;

  // API 返回 401
  if (pathname.startsWith('/api')) {
    return new NextResponse('Unauthorized', { status: 401 });
  }

  // 页面跳转 login
  const loginUrl = new URL('/login', request.url);
  loginUrl.searchParams.set('redirect', pathname);

  return NextResponse.redirect(loginUrl);
}

// ==============================
// Middleware 匹配
// ==============================

export const config = {
  matcher: [
    '/admin/:path*',
    '/api/admin/:path*'
  ],
};
