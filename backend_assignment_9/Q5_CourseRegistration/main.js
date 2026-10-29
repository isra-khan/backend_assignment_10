import { courses } from "./courses.js";
import { formatCourseSummary } from "./coursesUtils.js";

const { courseName, fees } = courses[0];
console.log(`Course Name: ${courseName}, Fee: ${fees}`);

const newCourse = {
    courseName: "Physics",
    instructor: "Isra Khan",
    duration: "4 months",
    fees: 20000
};
const originalCourse = courses[0];
const updatedCourse = { ...originalCourse, fees: 18000 };
const coursesWithNewCourse = [...courses, newCourse];

console.log("Original course:", originalCourse);
console.log("Updated course:", updatedCourse);
console.log("Course summaries:");
coursesWithNewCourse.forEach((course) => {
    console.log(formatCourseSummary(course));
});