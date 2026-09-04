import 'dart:io';

import 'package:flutter/material.dart';

import 'data/not_authenticated_exception.dart';
import 'sign_in_prompt_screen.dart';

/// Turns a caught error into copy a person can act on
/// (docs/FRONTEND_GUIDELINES.md §9) for any screen that calls an
/// authenticated API client. [NotAuthenticatedException] is the one case
/// every such call site needs to treat specially, distinct from
/// [fallback]: it means the request never reached the server at all
/// (AuthController.validAccessToken returned null), so "try again" is
/// actively wrong advice — retrying does nothing until the person signs
/// back in, which is what this says instead.
String describeAuthAwareError(Object e, String fallback) {
  if (e is NotAuthenticatedException) return "You're signed out — sign in to continue.";
  if (e is HttpException) return e.message;
  return fallback;
}

/// Shows [fallback] (or the sign-in-specific message, if [e] is a
/// [NotAuthenticatedException]) in a SnackBar. A [NotAuthenticatedException]
/// also gets a "Sign in" action right on the SnackBar — the actual path
/// forward FRONTEND_GUIDELINES.md §9 asks for, not just an explanation.
void showAuthAwareSnackBar(BuildContext context, Object e, String fallback) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(describeAuthAwareError(e, fallback)),
      action: e is NotAuthenticatedException
          ? SnackBarAction(
              label: 'Sign in',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SignInPromptScreen()),
              ),
            )
          : null,
    ),
  );
}
