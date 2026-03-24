# Postman – External API (13 Padel) – Quick start

You already imported the collection and environment. Follow these steps.

---

## Step 1: Select the environment

1. In Postman, look at the **top-right** of the window.
2. You’ll see a dropdown that might say **"No Environment"** or the name of another env.
3. Click that dropdown.
4. Choose **"External API (13 Padel)"** (or whatever name the imported environment has).
5. It should now show that name in the top-right. All requests in the collection will use this env.

---

## Step 2: Set your API key in the environment

1. Click the **dropdown** again (where you selected the environment).
2. Click the **eye icon** next to it, then **Edit** (or click the environment name and choose **Edit**).
3. In the **Variables** list, find the row for **apiKey**.
4. In the **CURRENT VALUE** column (or **Value**), replace `YOUR_API_KEY` with your real key:  
   `KwjhmoJeclST3ksORyL4dEBvF92NDtbM`
5. Click **Save**. Close the environment tab if you want.

Your env already has:
- **baseUrl**: `https://us-central1-padelcore-app.cloudfunctions.net`
- **locationId**: `SNLtAhHI5liqkjRnJehV` (13 Padel)
- **bookingDate**: `2026-03-15` (change this when you want to test another date)

---

## Step 3: Test “Get Location”

1. In the **left sidebar**, open your **Padel Booking – External API** collection (click the arrow if it’s collapsed).
2. Click the request **Get Location**.
3. The URL should show:  
   `{{baseUrl}}/getLocation?locationId={{locationId}}`  
   (Postman will replace these with the values from your env when you send.)
4. Click the blue **Send** button.
5. You should get **200 OK** and a JSON body with 13 Padel’s details: name, address, courts (court_1–court_4), openTime, closeTime, etc.

If you get **401**: the API key is wrong or missing. Go back to Step 2 and set **apiKey** correctly.

---

## Step 4: Test “Get Slots”

1. In the same collection, click **Get Slots**.
2. The URL uses `{{locationId}}` and `{{bookingDate}}`. The default date is **2026-03-15**. To use another date, either:
   - Edit the environment and change **bookingDate** to e.g. `2026-03-20`, then **Save**, or  
   - In the request URL, change the `date=` part manually for this one call.
3. Click **Send**.
4. You should get **200 OK** and JSON with a list of courts, each with **availableSlots** (e.g. `["8:00 AM", "8:30 AM", ...]`). Those are the bookable slots for that date.

---

## Step 5: Test “Create Booking”

1. Click **Create Booking** in the collection.
2. The **Body** tab should already have JSON like:
   - `locationId`: `{{locationId}}` (13 Padel)
   - `date`: `{{bookingDate}}`
   - `courts`: e.g. `"court_1": ["10:00 AM", "10:30 AM"]`
   - `firstName`, `lastName`, `phoneNumber`: change these if you want.
3. **Important:** Use slot strings that actually exist and are free. Either:
   - Copy slot strings from the **Get Slots** response (e.g. `"9:00 AM", "9:30 AM"`), or  
   - Keep the example `"court_1": ["10:00 AM", "10:30 AM"]` if that date has those slots free.
4. Click **Send**.
5. You should get **201** and a body like:  
   `{ "bookingId": "abc123...", "message": "Booking created" }`  
   Copy **bookingId**; you’ll use it for Cancel.
6. In your app (or Firestore), you should see this booking for 13 Padel.

---

## Step 6: Test “Cancel Booking”

1. Click **Cancel Booking** in the collection.
2. The URL has a query: `bookingId=BOOKING_ID_FROM_CREATE`. Replace **BOOKING_ID_FROM_CREATE** with the real **bookingId** you got from **Create Booking** (e.g. `abc123...`).
   - So the URL should look like:  
     `{{baseUrl}}/cancelBooking?bookingId=abc123...`
3. Click **Send**.
4. You should get **200** and `{ "message": "Booking cancelled" }`. The booking will disappear from your app and from Get Slots availability.

---

## Summary checklist

| Step | What to do |
|------|------------|
| 1 | Select environment **External API (13 Padel)** (top-right). |
| 2 | Edit that env and set **apiKey** to `KwjhmoJeclST3ksORyL4dEBvF92NDtbM`, then Save. |
| 3 | Send **Get Location** → expect 200 and 13 Padel details. |
| 4 | Send **Get Slots** → expect 200 and available slots (change **bookingDate** in env if needed). |
| 5 | Send **Create Booking** → use slots from Get Slots, then copy **bookingId**. |
| 6 | Send **Cancel Booking** → put that **bookingId** in the URL, then Send. |

All requests are already pointed at **13 Padel** (locationId `SNLtAhHI5liqkjRnJehV`). You only need to select the env, set the API key, and send.
