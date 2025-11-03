# Subscription Management System

## Overview
Added a comprehensive subscription management system that enables EV charging users to purchase monthly or yearly subscriptions for discounted charging rates. This independent feature provides significant value through cost savings and usage tracking while enhancing user engagement.

## Technical Implementation

### Key Functions Added:
- **purchase-subscription(plan-id)**: Allows users to buy subscription plans with token payment
- **cancel-subscription()**: Enables users to deactivate their active subscriptions
- **toggle-auto-renew()**: Manages automatic subscription renewal preferences
- **use-subscription-kwh(amount)**: Tracks kWh usage against subscription allowances
- **create-custom-plan()**: Admin function to create new subscription tiers
- **toggle-plan-availability()**: Admin function to enable/disable plans

### Data Structures Added:
- **user-subscriptions**: Maps user principals to subscription details (plan type, duration, usage)
- **subscription-plans**: Maps plan IDs to plan specifications (pricing, allowances, discounts)
- **Revenue tracking**: Monitors total subscription income for analytics

### Default Plans:
1. **Monthly Basic**: 100 kWh, 15% discount, 1000 tokens (~30 days)
2. **Yearly Standard**: 1500 kWh, 25% discount, 10000 tokens (~365 days)  
3. **Premium Yearly**: 3000 kWh, 35% discount, 18000 tokens (~365 days)

## Testing & Validation
- ✅ Contract passes clarinet check
- ✅ All npm tests successful
- ✅ CI/CD pipeline configured
- ✅ Clarity v3 compliant with proper error handling

## Features:
- Independent subscription management (no cross-contract dependencies)
- Discount calculation and application
- Usage tracking and allowance management
- Flexible plan creation and administration
- Revenue analytics and reporting
- Auto-renewal management